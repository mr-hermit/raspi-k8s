#!/usr/bin/env bash
# scripts/healthcheck.sh — Raspberry Pi K8s lab cluster health check
#
# Run from your control machine. Reads inventory.ini for node IPs and NAS config.
# SSH keys must be configured for the lab nodes.
#
# Usage:
#   ./scripts/healthcheck.sh [path/to/inventory.ini]
#
# Override kubeconfig:
#   KUBECONFIG=~/.kube/other-config ./scripts/healthcheck.sh

set -uo pipefail

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config-raspi}"
INVENTORY="${1:-inventory.ini}"

# ── Output ─────────────────────────────────────────────────────────────────────

[[ -t 1 ]] && {
  c_grn='\033[0;32m'; c_red='\033[0;31m'; c_yel='\033[1;33m'
  c_cyn='\033[0;36m'; c_gry='\033[0;90m'; c_bld='\033[1m'; c_nc='\033[0m'
} || {
  c_grn=''; c_red=''; c_yel=''; c_cyn=''; c_gry=''; c_bld=''; c_nc=''
}

_ok=0; _crit=0; _warn=0; _skip=0

# check LABEL STATE [DETAIL]
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
NAS_HOST="192.168.50.189"
NAS_ISCSI_PORT="3260"
NAS_DSM_PORT="5000"
declare -A HOST_ADDR
declare -A REACHABLE
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
    elif [[ "$line" =~ ^nas_host=([^[:space:]#]+) ]]; then
      NAS_HOST="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^nas_iscsi_port=([^[:space:]#]+) ]]; then
      NAS_ISCSI_PORT="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^nas_dsm_port=([^[:space:]#]+) ]]; then
      NAS_DSM_PORT="${BASH_REMATCH[1]}"
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

ssh_run() {
  local host="$1"; shift
  ssh "${SSH_OPTS[@]}" "${ANSIBLE_USER}@${host}" "$@" 2>/dev/null
}

svc_info() {
  ssh_run "$1" "systemctl show '$2' --property=LoadState,ActiveState 2>/dev/null" || true
}

# ── Check functions ────────────────────────────────────────────────────────────

check_nas() {
  section "NAS Connectivity  (${NAS_HOST})"
  if timeout 4 bash -c "echo > /dev/tcp/${NAS_HOST}/${NAS_ISCSI_PORT}" 2>/dev/null; then
    check "iSCSI  :${NAS_ISCSI_PORT}" "OK"
  else
    check "iSCSI  :${NAS_ISCSI_PORT}" "CRITICAL" "port unreachable"
  fi
  if timeout 4 bash -c "echo > /dev/tcp/${NAS_HOST}/${NAS_DSM_PORT}" 2>/dev/null; then
    check "DSM    :${NAS_DSM_PORT}" "OK"
  else
    check "DSM    :${NAS_DSM_PORT}" "CRITICAL" "port unreachable"
  fi
}

check_connectivity() {
  section "Node Connectivity"
  local name addr
  for name in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    addr="${HOST_ADDR[$name]}"
    if timeout 4 bash -c "echo > /dev/tcp/${addr}/22" 2>/dev/null; then
      REACHABLE["$name"]=1
      check "$name  ($addr)" "OK" "SSH port reachable"
    else
      check "$name  ($addr)" "CRITICAL" "port 22 unreachable — skipping further checks"
    fi
  done
}

check_ssh_auth() {
  section "SSH Key Authentication"
  local name addr
  for name in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    [[ -n "${REACHABLE[$name]+x}" ]] || continue
    addr="${HOST_ADDR[$name]}"
    if ssh_run "$addr" true; then
      check "$name  key auth" "OK"
    else
      check "$name  key auth" "CRITICAL" "key auth failed — check ~/.ssh/id_ed25519"
    fi
  done
}

check_iscsi() {
  section "iSCSI Storage  (/mnt/storage per node)"
  local name addr
  for name in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    [[ -n "${REACHABLE[$name]+x}" ]] || continue
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
    fi
  done
}

check_k8s_services() {
  section "Kubernetes Services  (per node)"
  local name addr
  for name in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    [[ -n "${REACHABLE[$name]+x}" ]] || continue
    addr="${HOST_ADDR[$name]}"
    for svc in crio kubelet; do
      local info load active
      info=$(svc_info "$addr" "$svc")
      load=$(echo   "$info" | grep LoadState   | cut -d= -f2)
      active=$(echo "$info" | grep ActiveState | cut -d= -f2)
      if   [[ "$load" == "not-found" || -z "$load" ]]; then
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

  local cp="${CONTROL_NODES[0]:-}"
  if [[ -n "$cp" && -z "${REACHABLE[$cp]+x}" ]]; then
    check "control plane" "CRITICAL" "unreachable — skipping all cluster checks"
    return
  fi

  if [[ ! -f "$KUBECONFIG" ]]; then
    local cp_addr="${HOST_ADDR[${CONTROL_NODES[0]:-}]:-rasserv01}"
    check "kubeconfig" "NOT_CONFIGURED" \
      "run: scp ${ANSIBLE_USER}@${cp_addr}:~/.kube/config $KUBECONFIG"
    return
  fi

  if ! kubectl cluster-info 2>/dev/null | grep -q "is running"; then
    check "API server" "CRITICAL" "unreachable"
    return
  fi
  check "API server" "OK"

  # Node readiness
  while read -r node status roles _rest; do
    [[ "$status" == "Ready" ]] \
      && check "node  $node" "OK"       "roles: $roles" \
      || check "node  $node" "CRITICAL" "status: $status"
  done < <(kubectl get nodes --no-headers 2>/dev/null)

  # Control plane components
  for comp in etcd kube-apiserver kube-scheduler kube-controller-manager; do
    local total ready
    total=$(kubectl get pods -n kube-system -l "component=${comp}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ "$total" -eq 0 ]] && continue
    ready=$(kubectl get pods -n kube-system -l "component=${comp}" --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$ready" -eq "$total" ]] \
      && check "control-plane  ${comp}" "OK" \
      || check "control-plane  ${comp}" "CRITICAL" "${ready}/${total} running"
  done

  # Calico
  for cal_ns in calico-system calico-apiserver; do
    if kubectl get namespace "$cal_ns" &>/dev/null 2>&1; then
      local total running
      total=$(kubectl get pods -n "$cal_ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      running=$(kubectl get pods -n "$cal_ns" --no-headers 2>/dev/null | grep -c "Running" || true)
      [[ "$running" -eq "$total" && "$total" -gt 0 ]] \
        && check "Calico  ${cal_ns}" "OK"      "${running}/${total} running" \
        || check "Calico  ${cal_ns}" "WARNING" "${running}/${total} running"
    fi
  done

  # Metrics Server
  local ms_ready
  ms_ready=$(kubectl get deployment metrics-server -n kube-system \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  if   [[ -z "$ms_ready" ]];    then check "Metrics Server" "NOT_CONFIGURED"
  elif [[ "$ms_ready" -ge 1 ]]; then check "Metrics Server" "OK"
  else                               check "Metrics Server" "CRITICAL" "0 replicas ready"
  fi
}

check_storage() {
  section "Storage"

  if [[ ! -f "$KUBECONFIG" ]]; then
    check "storage checks" "NOT_CONFIGURED" "no kubeconfig"
    return
  fi

  # StorageClasses
  local sc_count=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local sc_name sc_prov sc_def=""
    sc_name=$(echo "$line" | awk '{print $1}')
    sc_prov=$(echo "$line" | awk '{print $2}')
    [[ "$line" == *"(default)"* ]] && sc_def=" (default)"
    check "StorageClass  ${sc_name}${sc_def}" "OK" "${sc_prov}"
    ((sc_count++)) || true
  done < <(kubectl get storageclass --no-headers 2>/dev/null || true)
  [[ "$sc_count" -eq 0 ]] && check "StorageClasses" "CRITICAL" "none found"

  # PVCs across all namespaces
  local total_pvcs unbound_pvcs
  total_pvcs=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  unbound_pvcs=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -vc '\bBound\b' || true)
  if   [[ "$total_pvcs"   -eq 0 ]]; then check "PersistentVolumeClaims" "NOT_CONFIGURED" "none"
  elif [[ "$unbound_pvcs" -eq 0 ]]; then check "PersistentVolumeClaims" "OK"             "all ${total_pvcs} bound"
  else                                    check "PersistentVolumeClaims" "CRITICAL"       "${unbound_pvcs}/${total_pvcs} unbound"
  fi

  # Longhorn
  if ! kubectl get namespace longhorn-system &>/dev/null 2>&1; then
    check "Longhorn" "NOT_CONFIGURED"
  else
    local lh_total lh_running
    lh_total=$(kubectl get pods -n longhorn-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
    lh_running=$(kubectl get pods -n longhorn-system --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$lh_running" -eq "$lh_total" && "$lh_total" -gt 0 ]] \
      && check "Longhorn pods" "OK"      "${lh_running}/${lh_total} running" \
      || check "Longhorn pods" "WARNING" "${lh_running}/${lh_total} running"

    local lh_vols lh_degraded
    lh_vols=$(kubectl get volumes.longhorn.io -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    lh_degraded=$(kubectl get volumes.longhorn.io -A --no-headers 2>/dev/null \
      | awk '$NF != "healthy" && $NF != "detached"' | wc -l | tr -d ' ')
    if   [[ "$lh_vols"     -eq 0 ]]; then check "Longhorn volumes" "NOT_CONFIGURED" "none provisioned"
    elif [[ "$lh_degraded" -eq 0 ]]; then check "Longhorn volumes" "OK"             "all ${lh_vols} healthy"
    else                                   check "Longhorn volumes" "CRITICAL"       "${lh_degraded}/${lh_vols} degraded"
    fi
  fi

  # Synology CSI
  if ! kubectl get namespace synology-csi &>/dev/null 2>&1; then
    check "Synology CSI" "NOT_CONFIGURED"
  else
    local csi_total csi_running
    csi_total=$(kubectl get pods -n synology-csi --no-headers 2>/dev/null | wc -l | tr -d ' ')
    csi_running=$(kubectl get pods -n synology-csi --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$csi_running" -eq "$csi_total" && "$csi_total" -gt 0 ]] \
      && check "Synology CSI pods" "OK"      "${csi_running}/${csi_total} running" \
      || check "Synology CSI pods" "WARNING" "${csi_running}/${csi_total} running"

    kubectl get storageclass synology-iscsi &>/dev/null 2>&1 \
      && check "StorageClass synology-iscsi" "OK" \
      || check "StorageClass synology-iscsi" "CRITICAL" "missing — run --tags csi_storageclass"
  fi
}

check_addons() {
  section "Addons"

  if [[ ! -f "$KUBECONFIG" ]]; then
    check "addon checks" "NOT_CONFIGURED" "no kubeconfig"
    return
  fi

  local cp_addr="${HOST_ADDR[${CONTROL_NODES[0]:-}]:-}"

  # Ingress
  if ! kubectl get namespace ingress-nginx &>/dev/null 2>&1; then
    check "Ingress (nginx)" "NOT_CONFIGURED"
  else
    local t r
    t=$(kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | wc -l | tr -d ' ')
    r=$(kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$r" -eq "$t" && "$t" -gt 0 ]] \
      && check "Ingress nginx" "OK"      "${r}/${t} running" \
      || check "Ingress nginx" "WARNING" "${r}/${t} running"
  fi

  # cert-manager
  if ! kubectl get namespace cert-manager &>/dev/null 2>&1; then
    check "cert-manager" "NOT_CONFIGURED"
  else
    local t r
    t=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
    r=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$r" -eq "$t" && "$t" -gt 0 ]] \
      && check "cert-manager" "OK"      "${r}/${t} running" \
      || check "cert-manager" "WARNING" "${r}/${t} running"
  fi

  # Monitoring + Grafana
  if ! kubectl get namespace monitoring &>/dev/null 2>&1; then
    check "Monitoring" "NOT_CONFIGURED"
  else
    local t r
    t=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l | tr -d ' ')
    r=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$r" -eq "$t" && "$t" -gt 0 ]] \
      && check "Monitoring pods" "OK"      "${r}/${t} running" \
      || check "Monitoring pods" "WARNING" "${r}/${t} running"
    if [[ -n "$cp_addr" ]]; then
      curl -sf --max-time 5 "http://${cp_addr}:32000/api/health" -o /dev/null 2>/dev/null \
        && check "Grafana  :32000" "OK" \
        || check "Grafana  :32000" "WARNING" "not responding"
    fi
  fi

  # Registry
  if ! kubectl get namespace registry &>/dev/null 2>&1; then
    check "Registry" "NOT_CONFIGURED"
  else
    local t r
    t=$(kubectl get pods -n registry --no-headers 2>/dev/null | wc -l | tr -d ' ')
    r=$(kubectl get pods -n registry --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$r" -eq "$t" && "$t" -gt 0 ]] \
      && check "Registry pods" "OK"      "${r}/${t} running" \
      || check "Registry pods" "WARNING" "${r}/${t} running"
    if [[ -n "$cp_addr" ]]; then
      if curl -sf --max-time 5 "http://${cp_addr}:30500/v2/_catalog" -o /dev/null 2>/dev/null; then
        local repos
        repos=$(curl -sf --max-time 5 "http://${cp_addr}:30500/v2/_catalog" 2>/dev/null \
          | grep -o '"[^"]*"' | grep -vc '"repositories"' 2>/dev/null || echo "?")
        check "Registry API  :30500" "OK" "${repos} image(s) stored"
      else
        check "Registry API  :30500" "CRITICAL" "not responding"
      fi
    fi
  fi

  # Dashboard
  if kubectl get namespace headlamp &>/dev/null 2>&1; then
    local t r
    t=$(kubectl get pods -n headlamp --no-headers 2>/dev/null | wc -l | tr -d ' ')
    r=$(kubectl get pods -n headlamp --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$r" -eq "$t" && "$t" -gt 0 ]] \
      && check "Dashboard (headlamp)" "OK"      "${r}/${t} running" \
      || check "Dashboard (headlamp)" "WARNING" "${r}/${t} running"
  elif kubectl get namespace kubernetes-dashboard &>/dev/null 2>&1; then
    local t r
    t=$(kubectl get pods -n kubernetes-dashboard --no-headers 2>/dev/null | wc -l | tr -d ' ')
    r=$(kubectl get pods -n kubernetes-dashboard --no-headers 2>/dev/null | grep -c "Running" || true)
    [[ "$r" -eq "$t" && "$t" -gt 0 ]] \
      && check "Dashboard (k8s-dashboard)" "OK"      "${r}/${t} running" \
      || check "Dashboard (k8s-dashboard)" "WARNING" "${r}/${t} running"
  else
    check "Dashboard" "NOT_CONFIGURED"
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

  check_nas
  check_connectivity
  check_ssh_auth
  check_iscsi
  check_k8s_services
  check_k8s_cluster
  check_storage
  check_addons

  printf "\n${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n"
  printf "  ${c_grn}%d OK${c_nc}  |  ${c_red}%d CRITICAL${c_nc}  |  ${c_yel}%d WARNING${c_nc}  |  ${c_cyn}%d NOT CONFIGURED${c_nc}\n" \
    "$_ok" "$_crit" "$_warn" "$_skip"
  printf "${c_bld}══════════════════════════════════════════════════════════════${c_nc}\n\n"

  [[ "$_crit" -gt 0 ]] && return 1 || return 0
}

main "$@"
