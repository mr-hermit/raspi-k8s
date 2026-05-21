#!/usr/bin/env bash
# scripts/iscsi-troubleshoot.sh
#
# Diagnose iSCSI login/mount issues on a single lab node from the control machine.
#
# Usage:
#   ./scripts/iscsi-troubleshoot.sh <node_name> [inventory.ini]
#   ./scripts/iscsi-troubleshoot.sh --fix <node_name> [inventory.ini]
#
# Examples:
#   ./scripts/iscsi-troubleshoot.sh worker_node_1
#   ./scripts/iscsi-troubleshoot.sh --fix worker_node_2 inventory.ini

set -uo pipefail

DO_FIX=0
if [[ "${1:-}" == "--fix" ]]; then
  DO_FIX=1
  shift
fi

NODE_NAME="${1:-}"
INVENTORY="${2:-inventory.ini}"

if [[ -z "$NODE_NAME" ]]; then
  echo "Usage: $0 [--fix] <node_name> [inventory.ini]"
  exit 1
fi

if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: inventory not found: $INVENTORY"
  exit 1
fi

ANSIBLE_USER="ubuntu"
NAS_HOST=""
NAS_ISCSI_PORT="3260"
declare -A HOST_ADDR

group=""
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
  elif [[ "$line" =~ ^([^[:space:]=#\[]+)[[:space:]]+ansible_host=([^[:space:]#]+) ]]; then
    name="${BASH_REMATCH[1]}"
    addr="${BASH_REMATCH[2]}"
    HOST_ADDR["$name"]="$addr"
  fi
done < "$INVENTORY"

if [[ -z "${HOST_ADDR[$NODE_NAME]+x}" ]]; then
  echo "ERROR: node '$NODE_NAME' not found in $INVENTORY"
  echo "Known nodes:"
  for n in "${!HOST_ADDR[@]}"; do
    echo "  - $n (${HOST_ADDR[$n]})"
  done | sort
  exit 1
fi

NODE_ADDR="${HOST_ADDR[$NODE_NAME]}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=7 -o BatchMode=yes -o LogLevel=ERROR)
ssh_run() {
  local host="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${ANSIBLE_USER}@${host}" "$@"
}

echo "iSCSI troubleshoot target"
echo "  node:      $NODE_NAME"
echo "  address:   $NODE_ADDR"
echo "  ssh user:  $ANSIBLE_USER"
echo "  nas:       ${NAS_HOST:-<not-set>}:$NAS_ISCSI_PORT"
echo

if ! timeout 4 bash -c "echo > /dev/tcp/${NODE_ADDR}/22" 2>/dev/null; then
  echo "ERROR: node SSH port is unreachable: $NODE_ADDR:22"
  exit 2
fi

if ! ssh_run "$NODE_ADDR" "true"; then
  echo "ERROR: SSH auth failed for ${ANSIBLE_USER}@${NODE_ADDR}"
  exit 3
fi

read -r -d '' REMOTE_DIAG <<'EOF' || true
set -u

echo "==== host ===="
hostnamectl --static 2>/dev/null || hostname
uname -a

echo
echo "==== services ===="
for svc in iscsid open-iscsi nas-wait mnt-storage.mount; do
  printf "[%s] enabled=" "$svc"
  systemctl is-enabled "$svc" 2>/dev/null || printf "n/a"
  printf " active="
  systemctl is-active "$svc" 2>/dev/null || printf "unknown"
  printf "\n"
done

echo
echo "==== iscsi sessions ===="
iscsiadm -m session 2>/dev/null || echo "(no active sessions)"

echo
echo "==== iscsi node startup policy ===="
if iscsiadm -m node >/dev/null 2>&1; then
  while IFS= read -r row; do
    portal="$(awk '{print $1}' <<<"$row")"
    target="$(awk '{print $2}' <<<"$row")"
    startup="$(iscsiadm -m node -T "$target" -p "$portal" -o show 2>/dev/null | awk -F' = ' '/node.startup/{print $2; exit}')"
    printf "%s %s startup=%s\n" "$portal" "$target" "${startup:-unknown}"
  done < <(iscsiadm -m node 2>/dev/null)
else
  echo "(no discovered nodes in open-iscsi DB)"
fi

echo
echo "==== mount state ===="
if mountpoint -q /mnt/storage; then
  echo "/mnt/storage mounted"
  findmnt /mnt/storage -o TARGET,SOURCE,FSTYPE,OPTIONS -n 2>/dev/null || true
  df -h /mnt/storage 2>/dev/null || true
else
  echo "/mnt/storage NOT mounted"
fi

echo
echo "==== fstab entry ===="
grep -E '(/mnt/storage|x-systemd\\.requires|x-systemd\\.after)' /etc/fstab || echo "(no /mnt/storage line found)"

echo
echo "==== nas reachability from node ===="
if command -v nc >/dev/null 2>&1; then
  nc -zw3 "__NAS_HOST__" __NAS_PORT__ >/dev/null 2>&1 && echo "NAS iSCSI port reachable" || echo "NAS iSCSI port unreachable"
else
  timeout 4 bash -c "echo > /dev/tcp/__NAS_HOST__/__NAS_PORT__" 2>/dev/null && echo "NAS iSCSI port reachable" || echo "NAS iSCSI port unreachable"
fi

echo
echo "==== boot logs (iscsi + mount) ===="
journalctl -b --no-pager -u open-iscsi -u iscsid -u mnt-storage.mount -n 120 2>/dev/null || true
EOF

REMOTE_DIAG="${REMOTE_DIAG//__NAS_HOST__/${NAS_HOST:-127.0.0.1}}"
REMOTE_DIAG="${REMOTE_DIAG//__NAS_PORT__/${NAS_ISCSI_PORT}}"

echo "Running diagnostics on ${NODE_NAME} ..."
ssh_run "$NODE_ADDR" "bash -s" <<< "$REMOTE_DIAG"

if [[ "$DO_FIX" -eq 1 ]]; then
  echo
  echo "Applying safe recovery actions on ${NODE_NAME} ..."
  read -r -d '' REMOTE_FIX <<'EOF' || true
set -euo pipefail

sudo systemctl daemon-reload
sudo systemctl restart iscsid
sudo systemctl restart open-iscsi

# First try a deterministic login to the target that matches this node hostname.
# This handles cases where node.startup is not set to automatic yet.
node_host="$(hostnamectl --static 2>/dev/null || hostname)"
discovery_out="$(iscsiadm -m discovery -t sendtargets -p __NAS_HOST__:__NAS_PORT__ 2>/dev/null || true)"
target_iqn="$(printf '%s\n' "$discovery_out" | grep -F "$node_host" | awk '{print $2}' | head -1)"

if [[ -n "$target_iqn" ]]; then
  echo "Discovered node target: $target_iqn"
  sudo iscsiadm -m node -T "$target_iqn" -p __NAS_HOST__:__NAS_PORT__ \
    -o update -n node.startup -v automatic || true
  sudo iscsiadm -m node -T "$target_iqn" -p __NAS_HOST__:__NAS_PORT__ --login || true
else
  echo "No node-specific target found from discovery for hostname '$node_host'"
fi

# Fallback path for any already-marked automatic nodes.
sudo iscsiadm -m node --loginall=automatic || true
sudo systemctl restart mnt-storage.mount || sudo mount -a

echo "Recovery commands completed."
echo "Post-fix session status:"
iscsiadm -m session || true

echo "Post-fix mount status:"
if mountpoint -q /mnt/storage; then
  findmnt /mnt/storage -o TARGET,SOURCE,FSTYPE,OPTIONS -n
else
  echo "/mnt/storage still not mounted"
fi
EOF
  REMOTE_FIX="${REMOTE_FIX//__NAS_HOST__/${NAS_HOST:-127.0.0.1}}"
  REMOTE_FIX="${REMOTE_FIX//__NAS_PORT__/${NAS_ISCSI_PORT}}"
  ssh_run "$NODE_ADDR" "bash -s" <<< "$REMOTE_FIX"
fi

echo

echo "Done."
if [[ "$DO_FIX" -eq 0 ]]; then
  echo "Tip: rerun with --fix to restart iSCSI services, login automatic nodes, and remount /mnt/storage."
fi
