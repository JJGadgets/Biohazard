# AGENTS.md

## Project Overview

Biohazard is a homelab monorepo managing a single production Kubernetes cluster powered by Talos Linux, Cilium (CNI), Rook-Ceph (storage), Flux (GitOps), and Renovate (dependency updates). The goal is maximum automation with minimal manual intervention.

This is a personal "production" environment used to explore security solutions and infrastructure patterns in a real-world setting. "Glorifying jank that *works*" is the operating philosophy.

## Architecture

- **Cluster**: Biohazard (production Talos + Kubernetes 1.35.x)
- **GitOps**: Flux syncs desired state from this repo (two sources: GitHub `flux-system` + internal `soft-serve`)
- **Networking**: Cilium (CNI/NetworkPolicy/LoadBalancer), Multus (VLAN passthrough), BIRD (BGP), stunner (TURN/STUN), envoy-gateway + ingress-nginx, cloudflared
- **Storage**: Rook-Ceph (HA), VolSync (backups via Restic/rclone), democratic-csi (local-hostpath), external-snapshotter, snapscheduler, fstrim, csi-addons
- **DNS**: k8s-gateway (internal), external-dns (Cloudflare)
- **TLS**: cert-manager + trust-manager
- **Secrets**: SOPS-encrypted (age + PGP) in repo, runtime secrets via **external-secrets** operator pulling from **1Password** into Kubernetes Secrets
- **Databases**: CloudNativePG (Postgres, default + home clusters), Redis, Litestream, Mosquitto (MQTT)
- **Monitoring**: VictoriaMetrics + kube-prometheus-stack, Grafana, Alertmanager, Karma, node-exporter, smartctl-exporter, intel-gpu-exporter, fluentbit + Vector (log pipeline)
- **Autoscaling**: KEDA (event-driven)
- **Container registry cache**: Spegel
- **Hardware acceleration**: node-feature-discovery, intel-device-plugins, nvidia (for LLM/GPU workloads)
- **VMs**: KubeVirt (`_kubevirt/`), with AD and personal VMs
- **Auth/SSO**: Authentik (fronting ingress-nginx via outpost annotations)
- **Git server**: soft-serve (internal, used as a Flux source for app repos)
- **Config management**: `mise` for tool versions, `go-task` for tasks, `talhelper` for Talos config

## Directory Structure

```
kube/
├── bootstrap/flux/         # Initial Flux install manifests (flux-install-localhost.yaml, svc-metrics.yaml)
├── clusters/biohazard/
│   ├── config/             # ExternalSecret → K8s Secret for cluster vars
│   ├── flux/               # Top-level Flux Kustomization: GitRepository, externalsecret, patches
│   │   ├── flux-repo.yaml  # GitRepository + Kustomization with global patches (labelSelector-driven)
│   │   ├── externalsecret.yaml
│   │   └── kustomization.yaml
│   └── talos/              # talhelper config (talconfig.yaml) + SOPS-encrypted talsecret.yaml + watchdog.yaml
├── deploy/
│   ├── core/               # Essential cluster components (see Core Components below)
│   │   ├── _networking/    # cilium, multus, bird (BIRD currently active)
│   │   ├── db/             # pg, redis, litestream, mosquitto
│   │   ├── dns/            # external-dns, internal/k8s-gateway
│   │   ├── flux-system/    # flux healthcheck
│   │   ├── hardware/       # node-feature-discovery, intel-device-plugins, nvidia
│   │   ├── ingress/        # ingress-nginx, envoy-gateway, cloudflare, secrets-sync, stunner
│   │   ├── monitoring/     # victoria, kps, grafana, alertmanager, karma, fluentbit, vector, exporters, keda
│   │   ├── reloader/       # config-reloader for Secret/ConfigMap change detection
│   │   ├── secrets/        # external-secrets operator
│   │   ├── spegel/         # P2P registry cache
│   │   ├── storage/        # rook-ceph (+ cluster), democratic-csi, volsync, fstrim, snapshots, csi-addons
│   │   └── tls/            # cert-manager, trust-manager
│   ├── apps/               # ~60 user-facing apps (see App Pattern below)
│   └── vm/                 # KubeVirt VMs (_kubevirt, ad, jj)
├── repos/flux/             # HelmRepository and OCIRepository sources (helmpatches applied)
└── templates/test/         # Template for testing
.taskfiles/                 # go-task Taskfile includes (one per domain)
ostree/                     # NixOS/oStree host configurations (outside k8s scope)
dots/                       # Dotfiles (vim, k9s configs, etc.)
```

## Core Components (kube/deploy/core)

Components essential for the cluster to operate:

- **Networking** (`_networking/`): Cilium, Multus, BIRD
- **Storage** (`storage/`): Rook-Ceph (+ cluster), democratic-csi, VolSync, fstrim, external-snapshotter, snapscheduler, csi-addons
- **DNS** (`dns/`): external-dns, k8s-gateway
- **TLS** (`tls/`): cert-manager, trust-manager
- **Ingress** (`ingress/`): ingress-nginx, envoy-gateway, cloudflared tunnel, secrets-sync, stunner
- **Monitoring** (`monitoring/`): VictoriaMetrics, kube-prometheus-stack, Grafana, Alertmanager, Karma, metrics-server, fluentbit, Vector, node-exporter, smartctl-exporter, intel-gpu-exporter, KEDA
- **Databases** (`db/`): CloudNativePG, Redis, Litestream, Mosquitto
- **Hardware** (`hardware/`): node-feature-discovery, intel-device-plugins, nvidia
- **Secrets** (`secrets/`): external-secrets
- **Misc**: Spegel, Reloader, flux-system/healthcheck

> Note: Kyverno is currently **disabled** in the flux kustomization; native Kubernetes `MutatingAdmissionPolicy` is being adopted (see `runtime-config: admissionregistration.k8s.io/v1beta1=true` in talos config).

## App Pattern

Each app in `kube/deploy/apps/<app-name>/` follows this layout:

```
apps/<app-name>/
├── app/             # HelmRelease + values (often using bjw-s/labs app-template)
├── ks.yaml          # Flux Kustomization (often labeled for prune/wait/helmpatches/substitution behaviour)
├── kustomization.yaml
└── ns.yaml          # Namespace (apps live in the `apps` namespace by default; some get their own)
```

The apps in `kube/deploy/apps/kustomization.yaml` only declares the `apps` namespace; the actual app `Kustomization`s are pulled in by `kube/clusters/biohazard/flux/kustomization.yaml`.

## Key Tools

| Tool | Purpose |
|------|---------|
| `mise` | Tool version management (`.mise.toml`) — installs kubectl, flux, talos, k9s, sops, etc. |
| `task` | Task runner (Taskfile.dist.yaml + `.taskfiles/`) |
| `flux` | GitOps sync CLI |
| `flux-local` | Local Flux reconcile testing (pipx) |
| `talosctl` | Talos Linux node management |
| `talhelper` | Talos config rendering (`task talos:*`) |
| `kubectl` / `kubecolor` / `k9s` | Kubernetes CLI / colorized output / TUI |
| `cilium` | CNI troubleshooting CLI |
| `sops` | Secret encryption/decryption |
| `helm` / `kustomize` | Chart and manifest rendering |
| `yq` / `jq` | YAML/JSON manipulation (used heavily in taskfiles) |
| `1password` (`op`) | CLI used by tasks to fetch secrets from 1Password (e.g. `talos:run`) |
| `krr` | Kubernetes Resource Recommender |

## Task Namespaces

Each subdirectory in `.taskfiles/` is a namespace. Run with `task <namespace>:<task>` or its alias.

| Namespace | Alias | Use |
|-----------|-------|-----|
| `bootstrap` | `bs` | Cluster bootstrap |
| `cluster` | `ctx`, `init` | Multi-cluster ctx switching, cluster init |
| `flux` | `f` | Flux install, get-all-watch, cantWait (force ks to skip deps) |
| `k8s` | `k` | General k8s admin (wait-pod-pending, nsps, etc.) |
| `talos` | `t` | Talos config generation (talhelper) |
| `volsync` | `vs` | VolSync operations |
| `rook` | `r` | Rook-Ceph toolbox, disk wipe |
| `pg` | | CloudNativePG / Crunchy PGO master selection |
| `pulumi` | `pl` | Pulumi tasks (currently minimal) |
| `truenas` | `nas` | TrueNAS operations |
| `1p` | | 1Password helpers |

Useful one-offs: `task n d=path/to/dir f=filename` creates a dir + file, `task pwgen` generates passwords, `task gitconfig` configures git for this repo.

## Working with the Repo

### Adding a New Application

1. Create `kube/deploy/apps/<app-name>/` with the standard layout (`app/`, `ks.yaml`, `kustomization.yaml`, `ns.yaml`)
2. Most apps use the bjw-s/labs `app-template` Helm chart (HelmRelease under `app/`)
3. Add the app's kustomization path to `kube/clusters/biohazard/flux/kustomization.yaml`
4. Label the `Kustomization` appropriately (e.g. `prune.flux.home.arpa/disabled=true` to keep Flux from deleting the resource on removal)
5. Commit and push — Flux reconciles every 5m by default; Renovate will track the Helm chart version

### Secret Management

- **In-repo secrets** (Talos cluster secrets, kube secrets): SOPS-encrypted (age + PGP), see `.sops.yaml` for path rules. Use `sops` CLI to encrypt/decrypt.
- **Runtime secrets** (1Password-sourced): defined as `ExternalSecret` in `kube/clusters/biohazard/config/` and `flux/externalsecret.yaml`, synced via external-secrets operator from a `ClusterSecretStore` named `1p`.
- **Flux decryption**: Kustomizations use `decryption.provider: sops` with a `Secret` named `agekey` synced from 1Password.
- **NEVER commit plaintext secrets** or SOPS key material to the repo.

### Testing Changes Locally

```bash
# What Flux would apply
flux-local reconcile kustomization biohazard-cluster -f kube/clusters/biohazard/

# Generate Talos config
task talos:gen
# or with vars from 1Password
task talos:run

# Preview a single kustomization
kubectl kustomize kube/clusters/biohazard/flux | less
```

### Renovate

- Config in `.renovaterc.json5`, with shared presets in `.renovate/`
- Runs as a GitHub Action, opens PRs for Helm chart, container, and Flux version bumps
- Most updates automerge; digest pinning is enabled
- Uses semantic commits, runs in Asia/Singapore timezone
- Disabled paths: `**/archive/**`, `**/.archive/**`, `**/**.sops.**`, `./.git`, `**/ignore/**`

## Important Rules

1. **No plaintext secrets** — anything sensitive must be SOPS-encrypted
2. **GitOps only** — don't make imperative `kubectl apply` changes; everything lives in Git. The cluster is reconciled every 5 minutes
3. **`*.dist.yaml` pattern** — distribution files (`.dist.`) are committed; local copies (without `.dist.`) are gitignored and personalized via `cp *.dist.yaml *.yaml` and edit
4. **Cluster drift** — if you must make an emergency change, document it and reconcile to Git ASAP. `driftDetection.mode: warn` is set on HelmReleases
5. **`/spec/replicas` is ignored** by drift detection — safe to scale down for debugging
6. **HelmRelease defaults are patched globally** — intervals, timeouts, remediation, ingress annotations for Authentik are applied via `Kustomization` patches in `flux-repo.yaml`. Don't re-apply these per-app unless you need to override
7. **Don't reference private infra in PRs** — IPs (`IP_CLUSTER_VIP`, `IP_ROUTER_VLAN_K8S*`, `IP_HERCULES`, `IP_TRUENAS`) and DNS zones (`${DNS_CLUSTER}`, `${DNS_TS}`, `${DNS_MAIN}`) are stored as 1Password references, not in the repo

## Common Tasks

```bash
task                              # list all available tasks
task bs:<task>                    # Bootstrap
task cluster:ctx C=biohazard      # Switch kubectl context
task cluster:init                 # Initialise a cluster (Flux + config)
task f:get-all-watch              # watch Flux get all -A
task f:cantWait KS=<name> NS=flux-system   # Force a kustomization to skip deps/wait
task k8s:<task>                   # k8s admin
task talos:run                    # Regenerate talhelper config from 1Password secrets
task r:toolbox                    # Rook-Ceph toolbox shell
task vs:<task>                    # VolSync operations
task nas:<task>                   # TrueNAS operations
task pg:cnpg-rw APP=myapp         # Run command against CloudNativePG primary
```
