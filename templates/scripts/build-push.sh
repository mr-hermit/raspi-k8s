#!/usr/bin/env bash
# scripts/build-push.sh — Build a multi-platform Docker image and push to the lab registry
#
# Builds for linux/amd64 and linux/arm64 using Docker buildx, then pushes
# directly to the private registry running in the K8s cluster.
#
# Usage:
#   ./scripts/build-push.sh <build-dir> [name[:tag]]
#
# Examples:
#   ./scripts/build-push.sh ./apps/api              # image name = "api:latest"
#   ./scripts/build-push.sh ./apps/api myapi:v2.1.0
#
# Overrides:
#   REGISTRY=192.168.50.141:30500 ./scripts/build-push.sh ./apps/api
#   INVENTORY=/other/inventory.ini ./scripts/build-push.sh ./apps/api
#
# Prerequisites:
#   - Docker Desktop or Docker Engine with buildx plugin installed
#   - Registry must be in Docker's insecure-registries list (it runs over HTTP):
#
#       Docker Desktop → Settings → Docker Engine, add:
#         "insecure-registries": ["192.168.50.141:30500"]
#
#       Linux (/etc/docker/daemon.json), add:
#         { "insecure-registries": ["192.168.50.141:30500"] }
#       then: sudo systemctl restart docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${INVENTORY:-${SCRIPT_DIR}/../inventory.ini}"
BUILDER="raspi-lab"

# ── Colors (TTY only) ──────────────────────────────────────────────────────────

[[ -t 1 ]] && {
  c_grn='\033[0;32m'; c_red='\033[0;31m'; c_bld='\033[1m'; c_gry='\033[0;90m'; c_nc='\033[0m'
} || {
  c_grn=''; c_red=''; c_bld=''; c_gry=''; c_nc=''
}

info()  { printf "  ${c_gry}→${c_nc}  %s\n" "$*"; }
ok()    { printf "  ${c_grn}✓${c_nc}  %s\n" "$*"; }
die()   { printf "  ${c_red}✗${c_nc}  %s\n" "$*" >&2; exit 1; }

# ── Arguments ─────────────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && die "Usage: $0 <build-dir> [name[:tag]]"

BUILD_DIR="$1"
[[ -d "$BUILD_DIR" ]]              || die "directory not found: ${BUILD_DIR}"
[[ -f "${BUILD_DIR}/Dockerfile" ]] || die "no Dockerfile in ${BUILD_DIR}"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

IMAGE_REF="${2:-$(basename "$BUILD_DIR"):latest}"
[[ "$IMAGE_REF" == *:* ]] || IMAGE_REF="${IMAGE_REF}:latest"

# ── Registry address ──────────────────────────────────────────────────────────
# Read from inventory.ini; fall back to defaults; allow env override.

if [[ -z "${REGISTRY:-}" ]]; then
  CP_IP=""
  REG_PORT=""
  if [[ -f "$INVENTORY" ]]; then
    CP_IP=$(grep -E 'control_plane_node\s+ansible_host=' "$INVENTORY" \
      | grep -oE 'ansible_host=[^ #]+' | cut -d= -f2 | head -1 || true)
    REG_PORT=$(grep '^registry_nodeport=' "$INVENTORY" \
      | cut -d= -f2 | tr -d ' \r' | head -1 || true)
  fi
  CP_IP="${CP_IP:-192.168.50.141}"
  REG_PORT="${REG_PORT:-30500}"
  REGISTRY="${CP_IP}:${REG_PORT}"
fi

FULL_IMAGE="${REGISTRY}/${IMAGE_REF}"

# ── Preflight ─────────────────────────────────────────────────────────────────

docker info &>/dev/null || die "Docker is not running"
docker buildx version &>/dev/null || die "docker buildx not available — install Docker Desktop or the buildx plugin"

# ── Builder setup ─────────────────────────────────────────────────────────────
# Use a persistent docker-container builder so multi-platform builds work.
# The default builder only supports the host architecture.

if ! docker buildx inspect "$BUILDER" &>/dev/null; then
  info "Creating multi-platform builder '${BUILDER}'..."
  docker buildx create --name "$BUILDER" --driver docker-container --bootstrap --quiet
  ok "Builder '${BUILDER}' ready"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

printf "\n${c_bld}  Build${c_nc}\n"
printf "  %-12s %s\n" "dir:"       "$BUILD_DIR"
printf "  %-12s %s\n" "image:"     "$FULL_IMAGE"
printf "  %-12s %s\n" "platforms:" "linux/amd64, linux/arm64"
printf "  %-12s %s\n" "registry:"  "$REGISTRY"
echo

# ── Build + push ──────────────────────────────────────────────────────────────

START=$(date +%s)

docker buildx build \
  --builder  "$BUILDER" \
  --platform linux/amd64,linux/arm64 \
  --tag      "$FULL_IMAGE" \
  --push \
  "$BUILD_DIR"

ELAPSED=$(( $(date +%s) - START ))

echo
ok "Pushed ${FULL_IMAGE}  (${ELAPSED}s)"
printf "  %-12s docker pull %s\n" "pull:" "$FULL_IMAGE"
echo
