# AGENTS.md

## Project Overview

Biohazard is a homelab monorepo managing a production Kubernetes cluster powered by Talos Linux, Cilium (CNI), Rook-Ceph (storage), Flux (GitOps), and Renovate (dependency updates). The goal is maximum automation with minimal manual intervention.

## Architecture

- **Clusters**: Biohazard (production), Nuclear (test, currently offline)
- **GitOps**: Flux syncs desired state from this repo; Renovate opens PRs for version bumps
- **Storage**: Rook-Ceph (HA), VolSync (backups via Restic/rclone), democratic-csi (local)
- **Networking**: Cilium + Multus (VLAN passthrough), k8s-gateway (DNS), Ingress-NGINX, cloudflared (tunnels)
- **Secrets**: SOPS encrypted with age + PGP, managed via external-secrets operator (1Password backend)
- **Monitoring**: VictoriaMetrics + kube-prometheus-stack + Prometheus Operator
- **Policy**: Kyverno (validation, mutation, generation)
- **VMs**: KubeVirt for VMs within Kubernetes

## Directory Structure

```
kube/
├── bootstrap/     # Cluster bootstrap manifests
├── clusters/      # Per-cluster Flux Kustomizations (biohazard/, nuclear/)
├── deploy/        # Application deployments
│   └── core/      # Essential cluster components
├── repos/         # Helm repositories and OCI sources
└── templates/     # Reusable templates
.taskfiles/        # go-task task definitions per domain
ostree/            # NixOS/oStree configurations
dots/              # Dotfiles (vim, k9s configs, etc.)
```

## Key Tools

| Tool | Purpose |
|------|---------|
| `mise` | Tool version management (.mise.toml) |
| `task` | Task runner (Taskfile.dist.yaml) |
| `flux` / `flux-local` | GitOps sync and local testing |
| `talosctl` | Talos Linux cluster management |
| `talhelper` | Talos configuration helper |
| `kubectl` / `kubecolor` | Kubernetes CLI |
| `cilium` | CNI troubleshooting |
| `sops` | Secret encryption/decryption |
| `k9s` | Kubernetes TUI |
| `kyverno` | Policy engine |

## Working with the Repo

### Adding a New Application

1. Create directory under `kube/deploy/<category>/<app>/`
2. Use app-template (bjw-s-labs) or native Helm chart
3. Add to cluster Kustomization in `kube/clusters/biohazard/flux/deploy/<category>/kustomization.yaml`
4. Commit and push — Flux will reconcile, Renovate will track updates

### Secret Management

- Secrets under `kube/` are SOPS-encrypted per `.sops.yaml` rules
- NEVER commit unencrypted secrets or `.sops.yaml` key material
- Use `external-secrets` operator to sync from 1Password into Kubernetes
- For local testing, use `sops --decrypt` (requires age/PGP key access)

### Testing Changes Locally

```bash
# Preview what Flux would apply
flux-local reconcile kustomization biohazard-cluster -f kube/clusters/biohazard/

# Validate Talos config
talhelper bundle

# Run tasks
task <namespace>:<task>  # e.g. task flux:diff, task talos:gen
```

### Renovate

- Config in `.renovaterc.json5` with presets in `.renovate/`
- Runs as a GitHub Action, opens PRs for version bumps
- Most updates are automerged; breaking changes get manual-review PRs

## Important Rules

1. **No secrets in plaintext** — everything sensitive must be SOPS-encrypted
2. **GitOps only** — don't make imperative `kubectl apply` changes to the cluster; everything lives in Git
3. **Taskfile.dist.yaml pattern** — distribution files (`.dist.`) are committed; local copies (without `.dist.`) are gitignored and personalized
4. **Cluster drift** — if you must make an emergency change, document it and reconcile to Git ASAP
5. **Test Nuclear first** — major migrations should be tested on the Nuclear cluster before hitting production

## Common Tasks

```bash
task bs:<task>     # Bootstrap operations
task f:<task>      # Flux operations
task k:<task>      # Kubernetes operations
task t:<task>      # Talos operations
task vs:<task>     # VolSync operations
task r:<task>      # Rook-Ceph operations
task nas:<task>    # TrueNAS operations
```
