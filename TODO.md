# TODO

- Rename inventory alias `control_plane_node` to `control_node` for brevity and consistency with the group name `control_plane`
- Extend K8s setup to support multiple control plane nodes (HA control plane with stacked etcd via `kubeadm join --control-plane`), currently hardcoded to a single control plane
