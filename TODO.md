# TODO

- Rename inventory alias `control_plane_node` to `control_node` for brevity and consistency with the group name `control_plane`
- Extend K8s setup to support multiple control plane nodes (HA control plane with stacked etcd via `kubeadm join --control-plane`), currently hardcoded to a single control plane
- Add Ingress for private registry (blocked: needs either Let's Encrypt TLS or self-signed cert trust configured on every node before Docker/containerd will accept it)
- Obfuscate private data (credentials, IPs, hostnames) in files committed to the repository; `inventory.ini` and `LAB-CONTEXT.md` contain real values and must never be committed — add them to `.gitignore` and provide sanitized example/template counterparts instead
- Update iSCSI configuration on nodes to avoid using IPv6 for iSCSI discovery and connections, and ensure automatic login to the storage via IPv4, as partitions discovered by IPv6 causing a problems. 