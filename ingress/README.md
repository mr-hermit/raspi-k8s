# Ingress + cert-manager

Deploys:
- **Nginx Ingress Controller** — hostname-based routing to K8s services via a single entry point instead of per-service NodePorts
- **cert-manager** — automatic TLS certificate management with a self-signed ClusterIssuer pre-configured

## Prerequisites

`k8s/k8s-setup.yaml` completed.

## Usage

```bash
ansible-playbook -i inventory.ini ingress/ingress-setup.yaml
```

## Access

The Ingress Controller listens on every cluster node:

| Protocol | URL |
|----------|-----|
| HTTP  | `http://<any-node-ip>:30080` |
| HTTPS | `https://<any-node-ip>:30443` |

Point your local DNS or `/etc/hosts` at any node IP and route by hostname.

## Using Ingress in your services

Add an `Ingress` resource to your deployment and annotate it:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: selfsigned
spec:
  ingressClassName: nginx
  tls:
    - hosts: [my-app.local]
      secretName: my-app-tls
  rules:
    - host: my-app.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

## Selective execution

| Tag | What it runs |
|-----|--------------|
| `ingress`      | Nginx Ingress Controller |
| `cert_manager` | cert-manager + self-signed ClusterIssuer |

## Extending to Let's Encrypt

When exposing services externally, replace the ClusterIssuer with an ACME issuer:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your@email.com
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```
