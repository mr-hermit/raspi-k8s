#!/usr/bin/env bash
# healthcheck.sh — Raspberry Pi Lab cluster health check
#
# Validates server availability, SSH auth, iSCSI storage, Kubernetes services,
# cluster health, and the container registry — without reading Ansible logs.
#
# Run from your CONTROL MACHINE (laptop/WSL), not from a cluster node.
# Usage:  ./healthcheck.sh [path/to/inventory.ini]
#
# Environment:
#   KUBECONFIG_RASPI  path to raspi kubeconfig (default: ~/.kube/config-raspi)

set -uo pipefail

INVENTORY="${1:-inventory.ini}"
KUBECONFIG_RASPI="${KUBECONFIG_RASPI:-$HOME/.kube/config-raspi}"

# ── Output ─────────────────────────────────────────────────────────────────────

[[ -t 1 ]] && {
  c_grn='\033[0;32m'; c_red='\033[0;31m'; c_yel='\033[1;33m'
  c_cyn='\033[0;36m'; c_gry='\033[0;90m'; c_bld='\033[1m'; c_nc='\033[0m'
} || {
  c_grn=''; c_red=''; c_yel=''; c_cyn=''; c_gry=''; c_bld=''; c_nc=''
}

_ok=0; _crit=0; _warn=0; _skip=0

# check LABEL STATE [DETAIL]
# STATE: OK | CRITICAL | WARNING | NOT_CONFIGURED
check() {
  local label="$1" state="$2" detail="${3:-}"
  local color
  case "$state" in
    OK)             color="$c_grn"; _ok=$((_ok+1))     ;;
    CRITICAL)       color="$c_red"; _crit=$((_crit+1)) ;;
    WARNING)        color="$c_yel"; _warn=$((_warn+1)) ;;
    NOT_CONFIGURED) color="$c_cyn"; _skip=$((_skip+1)) ;;
    *)              color="$c_gry"; _skip=$((_skip+1)) ;;
  esac
  printf "  %-46s ${color}%-16s${c_nc}%s\n" "$label" "$state" "$detail"
}

section() {
  printf "\n${c_gry}──────────────────────────────────────────────────────────────${c_nc}\n"
  printf "  ${c_bld}%s${c_nc}\n" "$1"
  printf "${c_gry}──────────────────────────────────────────────────────────────${c_nc}\n"
}

# ── Inventory parser ───────────────────────────────────────────────────────────

ANSIBLE_USER="ubuntu"
declare -A HOST_ADDR   # inventory_name → ansible_host value
CONTROL_NODES=()
WORKER_NODES=()

parse_inventory() {
  [[ -f "$INVENTORY" ]] || { printf "ERROR: inventory not found: %s\n" "$INVENTORY"; exit 1; }
  local group=""
  while IFS= read -r line; do
    # Skip blank lines and comments
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

# ── SSH helper ─────────────────────────────────────────────────────────────────

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR)

# ssh_run HOST CMD... → runs CMD on HOST, returns its exit code
ssh_run() {
  local host="$1"; shift
  ssh "${SSH_OPTS[@]}" "${ANSIBLE_USER}@${host}" "$@" 2>/dev/null
}

# svc_info HOST SERVICE → outputs "LoadState=<val>\nActiveState=<val>"
svc_info() {
  ssh_run "$1" "systemctl show '$2' --property=LoadState,ActiveState 2>/dev/null" || true
}

# ── Check functions ────────────────────────────────────────────────────────────

check_connectivity() {
  section "Connectivity"
  local name addr
  for name in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    addr="${HOST_ADDR[$name]}"
    if timeout 4 bash -c "echo > /dev/tcp/${addr}/22" 2>/dev/null; then
      check "$name  ($addr)" "OK" "SSH port reachable"
    else
      check "$name  ($addr)" "CRITICAL" "port 22 unreachable"
    fi
  done
}

check_ssh_auth() {
  section "SSH Key Authentication"
  local name addr
  for name in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    addr="${HOST_ADDR[$name]}"
    if ssh_run "$addr" true; then
      check "$name  key auth" "OK"
    else
      check "$name  key auth" "CRITICAL" "key auth failed — check ~/.ssh/id_ed25519"
    fi
  done
}

check_iscsi() {
  section "iSCSI Storage"
  local name addr
  for name in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    addr="${HOST_ADDR[$name]}"

    if ! ssh_run "$addr" "command -v iscsiadm" &>/dev/null; then
      check "$name  iSCSI" "NOT_CONFIGURED" "open-iscsi not installed"
      continue
    fi

    local iscsi_state
    iscsi_state=$(ssh_run "$addr" "systemctl is-active open-iscsi 2>/dev/null" || echo "unknown")
    [[ "$iscsi_state" == "active" ]] \
      && check "$name  open-iscsi" "OK" \
      || check "$name  open-iscsi" "CRITICAL" "state: $iscsi_state"

    if ssh_run "$addr" "mountpoint -q /mnt/storage"; then
      local usage
      usage=$(ssh_run "$addr" "df -h /mnt/storage | awk 'NR==2{print \$3\"/\"\$2\" (\"\$5\")\"}'")
      check "$name  /mnt/storage" "OK" "$usage"
    else
      check "$name  /mnt/storage" "CRITICAL" "not mounted"
      continue
    fi

    # Count bind mounts sourced from the iSCSI volume
    local expected=4
    [[ "${CONTROL_NODES[0]:-}" == "$name" ]] && expected=5  # +etcd on control plane
    local actual
    actual=$(ssh_run "$addr" "mount | grep -c '/mnt/storage/' 2>/dev/null" || echo 0)
    [[ "$actual" -ge "$expected" ]] \
      && check "$name  bind mounts" "OK"      "${actual}/${expected}" \
      || check "$name  bind mounts" "WARNING" "${actual}/${expected} — some K8s dirs may be on SD card"
  done
}

check_k8s_services() {
  section "Kubernetes Services"
  local name addr
  for name in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    addr="${HOST_ADDR[$name]}"
    for svc in crio kubelet; do
      local info load active
      info=$(svc_info "$addr" "$svc")
      load=$(echo  "$info" | grep LoadState   | cut -d= -f2)
      active=$(echo "$info" | grep ActiveState | cut -d= -f2)
      if   [[ "$load"   == "not-found" || -z "$load" ]]; then
        check "$name  $svc" "NOT_CONFIGURED" "not installed"
      elif [[ "$active" == "active" ]]; then
        check "$name  $svc" "OK"
      else
        check "$name  $svc" "CRITICAL" "state: $active"
      fi
    done
  done
}

check_k8s_cluster() {
  section "Kubernetes Cluster"

  if [[ ! -f "$KUBECONFIG_RASPI" ]]; then
    check "kubeconfig" "NOT_CONFIGURED" \
      "run: scp ${ANSIBLE_USER}@${HOST_ADDR[${CONTROL_NODES[0]:-cp}]:-rasserv01}:~/.kube/config $KUBECONFIG_RASPI"
    return
  fi

  local kc="kubectl --kubeconfig=$KUBECONFIG_RASPI"

  # API server reachable?
  if ! $kc cluster-info 2>/dev/null | grep -q "is running"; then
    check "API server" "CRITICAL" "unreachable — is the cluster up?"
    return
  fi
  check "API server" "OK"

  # Node readiness
  while read -r node status roles _rest; do
    [[ "$status" == "Ready" ]] \
      && check "node  $node" "OK"       "roles: $roles" \
      || check "node  $node" "CRITICAL" "status: $status"
  done < <($kc get nodes --no-headers 2>/dev/null)

  # kube-system pods
  local total running
  total=$( $kc get pods -n kube-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
  running=$($kc get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || true)
  if   [[ "$total"   -eq 0 ]];            then check "kube-system pods" "NOT_CONFIGURED"
  elif [[ "$running" -eq "$total" ]];     then check "kube-system pods" "OK"      "${running}/${total} running"
  else                                         check "kube-system pods" "WARNING"  "${running}/${total} running"
  fi

  # Calico
  local cal_total cal_running
  cal_total=$($kc get pods -n calico-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$cal_total" -gt 0 ]]; then
    cal_running=$($kc get pods -n calico-system --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$cal_running" -eq "$cal_total" ]] \
      && check "Calico CNI" "OK"      "${cal_running}/${cal_total} pods" \
      || check "Calico CNI" "WARNING" "${cal_running}/${cal_total} pods running"
  else
    check "Calico CNI" "NOT_CONFIGURED" "no pods found in calico-system"
  fi

  # Metrics Server
  local ms_ready
  ms_ready=$($kc get deployment metrics-server -n kube-system \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  if   [[ -z "$ms_ready" ]];       then check "Metrics Server" "NOT_CONFIGURED"
  elif [[ "$ms_ready" -ge 1 ]];    then check "Metrics Server" "OK"
  else                                   check "Metrics Server" "CRITICAL" "0 replicas ready"
  fi

  # Prometheus + Grafana (kube-prometheus-stack)
  local mon_total mon_running
  mon_total=$($kc get pods -n monitoring --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$mon_total" -eq 0 ]]; then
    check "Prometheus / Grafana" "NOT_CONFIGURED"
  else
    mon_running=$($kc get pods -n monitoring --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$mon_running" -eq "$mon_total" ]] \
      && check "Prometheus / Grafana" "OK"      "${mon_running}/${mon_total} pods" \
      || check "Prometheus / Grafana" "WARNING" "${mon_running}/${mon_total} pods running"
  fi
}

check_registry() {
  section "Container Registry"

  if [[ ! -f "$KUBECONFIG_RASPI" ]]; then
    check "registry" "NOT_CONFIGURED" "no kubeconfig — skipping"
    return
  fi

  local kc="kubectl --kubeconfig=$KUBECONFIG_RASPI"

  local reg_ready
  reg_ready=$($kc get deployment registry -n registry \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

  if   [[ -z "$reg_ready" ]];    then check "registry" "NOT_CONFIGURED"; return
  elif [[ "$reg_ready" -ge 1 ]]; then check "registry deployment" "OK"
  else                                check "registry deployment" "CRITICAL" "0 replicas ready"; return
  fi

  local cp_addr="${HOST_ADDR[${CONTROL_NODES[0]}]}"
  local repos
  if curl -sf --connect-timeout 3 "http://${cp_addr}:30500/v2/" &>/dev/null; then
    repos=$(curl -sf --connect-timeout 3 "http://${cp_addr}:30500/v2/_catalog" 2>/dev/null \
      | grep -o '"[^"]*"' | grep -vc '"repositories"' 2>/dev/null || echo "?")
    check "registry API  ${cp_addr}:30500" "OK" "${repos} image(s) stored"
  else
    check "registry API  ${cp_addr}:30500" "CRITICAL" "HTTP /v2/ not responding"
  fi
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  parse_inventory

  local all_nodes=("${CONTROL_NODES[@]}" "${WORKER_NODES[@]}")

  printf "\n${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n"
  printf "  ${c_bld}Raspberry Pi Lab — Health Check${c_nc}\n"
  printf "  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf "  Inventory: %-24s Nodes: %s\n" "$INVENTORY" "${all_nodes[*]}"
  printf "${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n"

  check_connectivity
  check_ssh_auth
  check_iscsi
  check_k8s_services
  check_k8s_cluster
  check_registry

  printf "\n${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n"
  printf "  ${c_grn}%d OK${c_nc}  |  ${c_red}%d CRITICAL${c_nc}  |  ${c_yel}%d WARNING${c_nc}  |  ${c_cyn}%d NOT CONFIGURED${c_nc}\n" \
    "$_ok" "$_crit" "$_warn" "$_skip"
  printf "${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n\n"

  [[ "$_crit" -gt 0 ]] && return 1 || return 0
}

main "$@"
