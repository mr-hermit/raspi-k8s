#!/usr/bin/env python3
"""Generate LAB-CONTEXT.md from inventory.ini.

Usage:
  python scripts/generate-lab-context.py

Optional:
  python scripts/generate-lab-context.py \
    --inventory inventory.ini \
    --template templates/LAB-CONTEXT.md.template \
    --output LAB-CONTEXT.md
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Set, Tuple


def parse_inventory(path: Path) -> Tuple[Dict[str, str], List[Tuple[str, str]], List[Tuple[str, str]]]:
    vars_map: Dict[str, str] = {}
    control_nodes: List[Tuple[str, str]] = []
    worker_nodes: List[Tuple[str, str]] = []

    current_section = ""
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("[") and line.endswith("]"):
            current_section = line[1:-1].strip().lower()
            continue

        if current_section == "all:vars" and "=" in line:
            key, val = line.split("=", 1)
            vars_map[key.strip()] = val.strip()
            continue

        if current_section in {"control_plane", "worker_node"}:
            parts = line.split()
            if not parts:
                continue
            alias = parts[0]
            host = alias
            for token in parts[1:]:
                if token.startswith("ansible_host="):
                    host = token.split("=", 1)[1].strip()
                    break
            if current_section == "control_plane":
                control_nodes.append((alias, host))
            else:
                worker_nodes.append((alias, host))

    return vars_map, control_nodes, worker_nodes


def rows(nodes: List[Tuple[str, str]], role: str) -> str:
    if not nodes:
        return f"| <not-set> | {role} | <not-set> |"
    return "\n".join(f"| {name} | {role} | {host} |" for name, host in nodes)


# Addon → the Kubernetes namespace its Helm/manifest install creates.
# Detection: check if that namespace exists via `kubectl get namespace`.
_ADDON_NAMESPACES: Dict[str, str] = {
    "registry":     "registry",
    "ingress":      "ingress-nginx",
    "longhorn":     "longhorn-system",
    "synology-csi": "synology-csi",
    "monitoring":   "monitoring",
    "dashboard":    "headlamp",
}


def detect_deployed_addons(kubeconfig: str | None) -> Set[str]:
    """Query the live cluster and return the set of detected addon names.

    Falls back to an empty set (with a warning) if kubectl is unavailable or
    the cluster cannot be reached.
    """
    if not shutil.which("kubectl"):
        print("WARNING: kubectl not found in PATH — addon detection skipped, all sections will be omitted.", flush=True)
        return set()

    import os
    env = {**os.environ}
    if kubeconfig:
        env["KUBECONFIG"] = kubeconfig

    try:
        result = subprocess.run(
            ["kubectl", "get", "namespaces", "-o", "name"],
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
    except subprocess.TimeoutExpired:
        print("WARNING: kubectl timed out — addon detection skipped.", flush=True)
        return set()
    except OSError as exc:
        print(f"WARNING: kubectl error ({exc}) — addon detection skipped.", flush=True)
        return set()

    if result.returncode != 0:
        print(f"WARNING: kubectl get namespaces failed — addon detection skipped.\n  {result.stderr.strip()}", flush=True)
        return set()

    existing = {line.removeprefix("namespace/").strip() for line in result.stdout.splitlines() if line.strip()}
    return {addon for addon, ns in _ADDON_NAMESPACES.items() if ns in existing}


def build_storage_profile_section(vars_map: Dict[str, str], addons: set) -> str:
    lines = [
        f"- Shared storage mount path: `{vars_map.get('iscsi_mount_point', '/mnt/storage')}`",
        f"- iSCSI initiator prefix: `{vars_map.get('iscsi_initiator_prefix', 'iqn.2024-01.lab.raspi')}`",
    ]
    if "synology-csi" in addons:
        nas_host = vars_map.get("nas_host", "<nas-host>")
        dsm_port = vars_map.get("nas_dsm_port", "5000")
        dsm_scheme = "https" if vars_map.get("nas_dsm_https", "false").lower() == "true" else "http"
        lines.append(f"- NAS: `{nas_host}` (DSM: `{dsm_scheme}://{nas_host}:{dsm_port}`)")
    lines.append("- Storage classes:")
    if "longhorn" in addons:
        replicas = vars_map.get("longhorn_replica_count", "2")
        lines.append(f"  - `longhorn` (distributed, {replicas} replicas, default)")
    if "synology-csi" in addons:
        lines.append("  - `synology-iscsi` (NAS CSI block storage)")
    lines.append("  - `local-storage` (node-pinned, always available)")
    return "\n".join(lines)


def build_network_endpoints_section(vars_map: Dict[str, str], addons: set, registry_address: str) -> str:
    lines = []
    if "registry" in addons:
        port = vars_map.get("registry_nodeport", "30500")
        lines.append(f"- Registry: `{registry_address}` (NodePort `{port}`)")
    if "ingress" in addons:
        lines.append(f"- Ingress HTTP NodePort: `{vars_map.get('ingress_http_nodeport', '30080')}`")
        lines.append(f"- Ingress HTTPS NodePort: `{vars_map.get('ingress_https_nodeport', '30443')}`")
    if "longhorn" in addons:
        lines.append(f"- Longhorn UI NodePort: `{vars_map.get('longhorn_ui_nodeport', '30700')}`")
    if "monitoring" in addons:
        lines.append(f"- Grafana NodePort: `{vars_map.get('grafana_nodeport', '32000')}`")
    return "\n".join(lines) if lines else "_No addon endpoints configured._"


def build_constraints_addon_notes(addons: set, cp_ip: str, registry_address: str) -> str:
    notes = []
    if "ingress" in addons:
        notes.append(
            "- Ingress hostnames require DNS/hosts mapping to node IPs."
            f" Add to `/etc/hosts` on your workstation:\n"
            f"  ```\n"
            f"  {cp_ip}  myapp.local\n"
            f"  ```"
        )
    if "registry" in addons:
        notes.append(
            f"- Registry `{registry_address}` is HTTP (no TLS)."
            " Configure your Docker client (`/etc/docker/daemon.json` or Docker Desktop settings):\n"
            "  ```json\n"
            f'  {{"insecure-registries": ["{registry_address}"]}}\n'
            "  ```\n"
            "  For CRI-O/containerd on cluster nodes this is already pre-configured by Ansible."
        )
    return "\n".join(notes)


def build_ai_storage_guidance(addons: set) -> str:
    lines = []
    if "longhorn" in addons:
        lines.append("  - failover-oriented stateful app: `longhorn`")
    if "synology-csi" in addons:
        lines.append("  - NAS-managed block volume per claim: `synology-iscsi`")
    lines.append("  - node-pinned singleton workload: `local-storage`")
    return "\n".join(lines)


def replacement_map(vars_map: Dict[str, str], control: List[Tuple[str, str]], workers: List[Tuple[str, str]], addons: Set[str]) -> Dict[str, str]:
    registry_port = vars_map.get("registry_nodeport", "30500")
    cp_host = control[0][1] if control else "<control-plane-host>"
    cp_name = control[0][0] if control else "<control-plane>"
    registry_address = f"{cp_host}:{registry_port}"

    return {
        "GENERATED_AT": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ"),
        "CONTROL_PLANE_HOST": cp_name,
        "CONTROL_PLANE_IP": cp_host,
        "CONTROL_PLANE_ROWS": rows(control, "Control Plane"),
        "WORKER_ROWS": rows(workers, "Worker"),
        "ANSIBLE_USER": vars_map.get("ansible_user", "<ssh-user>"),
        "NODE_MODEL": vars_map.get("node_model", "Raspberry Pi 5"),
        "KUBERNETES_VERSION": vars_map.get("kubernetes_version", "1.32"),
        "CRI_RUNTIME": vars_map.get("container_runtime", "CRI-O"),
        "CNI_NAME": vars_map.get("cni_name", "Calico"),
        "POD_CIDR": vars_map.get("pod_cidr", "10.244.0.0/16"),
        "REGISTRY_NODEPORT": registry_port,
        "REGISTRY_ADDRESS": registry_address,
        "INGRESS_HTTP_NODEPORT": vars_map.get("ingress_http_nodeport", "30080"),
        "INGRESS_HTTPS_NODEPORT": vars_map.get("ingress_https_nodeport", "30443"),
        "LONGHORN_UI_NODEPORT": vars_map.get("longhorn_ui_nodeport", "30700"),
        "GRAFANA_NODEPORT": vars_map.get("grafana_nodeport", "32000"),
        "KUBECONFIG_PATH": vars_map.get("kubeconfig_path", "~/.kube/config-raspi"),
        "STORAGE_PROFILE_SECTION": build_storage_profile_section(vars_map, addons),
        "NETWORK_ENDPOINTS_SECTION": build_network_endpoints_section(vars_map, addons, registry_address),
        "CONSTRAINTS_ADDON_NOTES": build_constraints_addon_notes(addons, cp_host, registry_address),
        "AI_STORAGE_GUIDANCE": build_ai_storage_guidance(addons),
    }


def render(template_text: str, values: Dict[str, str]) -> str:
    output = template_text
    for key, val in values.items():
        output = output.replace("{{" + key + "}}", val)
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate LAB-CONTEXT.md from inventory.ini")
    parser.add_argument("--inventory", default="inventory.ini", help="Path to local inventory file")
    parser.add_argument(
        "--template",
        default="templates/LAB-CONTEXT.md.template",
        help="Path to markdown template",
    )
    parser.add_argument(
        "--output",
        default="LAB-CONTEXT.md",
        help="Path to generated markdown output",
    )
    parser.add_argument("--kubeconfig", default=None, help="Path to kubeconfig (overrides KUBECONFIG env var)")
    args = parser.parse_args()

    inventory = Path(args.inventory)
    template = Path(args.template)
    output = Path(args.output)

    if not inventory.exists():
        raise SystemExit(f"Inventory file not found: {inventory}")
    if not template.exists():
        raise SystemExit(f"Template file not found: {template}")

    vars_map, control_nodes, worker_nodes = parse_inventory(inventory)

    kubeconfig = args.kubeconfig or vars_map.get("kubeconfig_path") or None
    addons = detect_deployed_addons(kubeconfig)
    if addons:
        print(f"Detected addons: {', '.join(sorted(addons))}", flush=True)
    else:
        print("No addons detected (cluster unreachable or kubectl unavailable).", flush=True)

    values = replacement_map(vars_map, control_nodes, worker_nodes, addons)
    rendered = render(template.read_text(encoding="utf-8"), values)

    output.write_text(rendered, encoding="utf-8")
    print(f"Generated {output} from {template} using {inventory}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
