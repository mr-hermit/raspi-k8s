#!/usr/bin/env bash
# shutdown.sh — Graceful Raspberry Pi Lab shutdown
#
# Drains Kubernetes workloads and powers off all cluster nodes in the correct
# order: workers first, then the control plane.
#
# Run from your CONTROL MACHINE (laptop/WSL), not from a cluster node.
# Usage:  ./scripts/shutdown.sh [path/to/inventory.ini]
#
# Environment:
#   KUBECONFIG_RASPI  path to raspi kubeconfig (default: ~/.kube/config-raspi)

set -uo pipefail

INVENTORY="${1:-inventory.ini}"
KUBECONFIG_RASPI="${KUBECONFIG_RASPI:-$HOME/.kube/config-raspi}"

# ── Output ─────────────────────────────────────────────────────────────────────

[[ -t 1 ]] && {
  c_grn='\033[0;32m'; c_red='\033[0;31m'; c_yel='\033[1;33m'
  c_gry='\033[0;90m'; c_bld='\033[1m'; c_nc='\033[0m'
} || {
  c_grn=''; c_red=''; c_yel=''; c_gry=''; c_bld=''; c_nc=''
}

log()  { printf "  ${c_bld}%s${c_nc}\n" "$*"; }
ok()   { printf "  ${c_grn}✔${c_nc}  %s\n" "$*"; }
warn() { printf "  ${c_yel}!${c_nc}  %s\n" "$*"; }
fail() { printf "  ${c_red}✘${c_nc}  %s\n" "$*"; }
step() {
  printf "\n${c_gry}──────────────────────────────────────────────────────────────${c_nc}\n"
  printf "  ${c_bld}%s${c_nc}\n" "$1"
  printf "${c_gry}──────────────────────────────────────────────────────────────${c_nc}\n"
}

# ── Inventory parser ───────────────────────────────────────────────────────────

ANSIBLE_USER="ubuntu"
declare -A HOST_ADDR
CONTROL_NODES=()
WORKER_NODES=()

parse_inventory() {
  [[ -f "$INVENTORY" ]] || { printf "ERROR: inventory not found: %s\n" "$INVENTORY"; exit 1; }
  local group=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
    if   [[ "$line" =~ ^\[([^\]:]+)\] ]]; then
      group="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^ansible_user=([^[:space:]#]+) ]]; then
      ANSIBLE_USER="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^([^[:space:]=#\[]+)[[:space:]]+ansible_host=([^[:space:]#]+) ]]; then
      local name="${BASH_REMATCH[1]}" host="${BASH_REMATCH[2]}"
      HOST_ADDR["$name"]="$host"
      [[ "$group" == "control_plane" ]] && CONTROL_NODES+=("$name")
      [[ "$group" == "worker_node"   ]] && WORKER_NODES+=("$name")
    fi
  done < "$INVENTORY"
}

# ── SSH / kubectl helpers ──────────────────────────────────────────────────────

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR)

ssh_run() { local host="$1"; shift; ssh "${SSH_OPTS[@]}" "${ANSIBLE_USER}@${host}" "$@" 2>/dev/null; }

is_reachable() { timeout 4 bash -c "echo > /dev/tcp/${1}/22" 2>/dev/null; }

kc() { kubectl --kubeconfig="$KUBECONFIG_RASPI" "$@"; }

# ── Drain a node via kubectl ───────────────────────────────────────────────────

drain_node() {
  local node_name="$1"

  # Resolve the K8s node name from the OS hostname (may differ from inventory alias)
  local k8s_name
  k8s_name=$(kc get nodes --no-headers -o custom-columns='NAME:.metadata.name' 2>/dev/null \
    | grep -F "${HOST_ADDR[$node_name]}" || true)

  # Fall back to matching by the inventory alias / hostname substring
  if [[ -z "$k8s_name" ]]; then
    k8s_name=$(kc get nodes --no-headers 2>/dev/null \
      | awk '{print $1}' | grep -F "${node_name##*-}" | head -1 || true)
  fi

  if [[ -z "$k8s_name" ]]; then
    warn "$node_name — node not found in cluster (already down or not joined)"
    return 0
  fi

  log "Draining $k8s_name ..."
  if kc drain "$k8s_name" \
      --ignore-daemonsets \
      --delete-emptydir-data \
      --timeout=60s \
      --force \
      2>&1 | sed 's/^/    /'; then
    ok "$node_name drained"
  else
    warn "$node_name drain had warnings — continuing shutdown"
  fi
}

# ── Power off a node ───────────────────────────────────────────────────────────

poweroff_node() {
  local name="$1" addr="${HOST_ADDR[$1]}"

  if ! is_reachable "$addr"; then
    warn "$name ($addr) — already unreachable, skipping"
    return 0
  fi

  log "Powering off $name ($addr) ..."
  if ssh_run "$addr" "sudo shutdown -h now"; then
    ok "$name — shutdown command sent"
  else
    fail "$name — shutdown command failed; try: ssh ${ANSIBLE_USER}@${addr} sudo shutdown -h now"
  fi
}

# ── Wait for a node to go offline ─────────────────────────────────────────────

wait_offline() {
  local name="$1" addr="${HOST_ADDR[$1]}" attempts=0
  printf "    waiting for %s to go offline " "$name"
  while is_reachable "$addr" && (( attempts < 15 )); do
    printf "."
    sleep 2
    (( attempts++ ))
  done
  printf "\n"
  is_reachable "$addr" \
    && warn "$name still reachable after shutdown — may take a moment longer" \
    || ok  "$name is offline"
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  parse_inventory

  local all_nodes=("${WORKER_NODES[@]}" "${CONTROL_NODES[@]}")

  printf "\n${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n"
  printf "  ${c_bld}${c_red}Raspberry Pi Lab — Shutdown${c_nc}\n"
  printf "  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf "  Workers : %s\n" "${WORKER_NODES[*]:-none}"
  printf "  Control : %s\n" "${CONTROL_NODES[*]:-none}"
  printf "${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n"

  # ── Confirmation ──────────────────────────────────────────────────────────
  printf "\n  ${c_yel}This will power off %d node(s).${c_nc}\n" "${#all_nodes[@]}"
  printf "  Type ${c_bld}yes${c_nc} to continue: "
  read -r confirm
  [[ "$confirm" == "yes" ]] || { printf "\n  Aborted.\n\n"; exit 0; }

  # ── Connectivity check ────────────────────────────────────────────────────
  step "Checking connectivity"
  local reachable=()
  for name in "${all_nodes[@]}"; do
    addr="${HOST_ADDR[$name]}"
    if is_reachable "$addr"; then
      ok "$name ($addr)"
      reachable+=("$name")
    else
      warn "$name ($addr) — unreachable, will skip"
    fi
  done

  if [[ "${#reachable[@]}" -eq 0 ]]; then
    fail "No nodes are reachable. Nothing to shut down."
    exit 1
  fi

  # ── Drain workers ─────────────────────────────────────────────────────────
  if [[ "${#WORKER_NODES[@]}" -gt 0 ]]; then
    step "Draining worker nodes"
    if [[ -f "$KUBECONFIG_RASPI" ]]; then
      for name in "${WORKER_NODES[@]}"; do
        drain_node "$name"
      done
    else
      warn "No kubeconfig at $KUBECONFIG_RASPI — skipping drain (pods will be killed on shutdown)"
    fi
  fi

  # ── Shutdown workers ──────────────────────────────────────────────────────
  if [[ "${#WORKER_NODES[@]}" -gt 0 ]]; then
    step "Shutting down worker nodes"
    for name in "${WORKER_NODES[@]}"; do
      poweroff_node "$name"
    done
    for name in "${WORKER_NODES[@]}"; do
      wait_offline "$name"
    done
  fi

  # ── Drain + shutdown control plane ────────────────────────────────────────
  step "Shutting down control plane"
  for name in "${CONTROL_NODES[@]}"; do
    if [[ -f "$KUBECONFIG_RASPI" ]]; then
      drain_node "$name"
    fi
    poweroff_node "$name"
  done
  for name in "${CONTROL_NODES[@]}"; do
    wait_offline "$name"
  done

  # ── Done ──────────────────────────────────────────────────────────────────
  printf "\n${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n"
  printf "  ${c_grn}Lab shutdown complete.${c_nc}\n"
  printf "${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n\n"
}

main "$@"
