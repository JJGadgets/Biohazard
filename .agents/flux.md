# Flux, Multi-Cluster, Labels & Secrets

## Multi-Cluster

The repo is structured for multi-cluster. Each cluster gets its own `kube/clusters/<name>/` directory with its own `flux/kustomization.yaml` (master list) and `flux/flux-repo.yaml` (global patches). The archived `nuclear` cluster (`.archive/kube/clusters/nuclear/`) is a reference example showing the same pattern: its `flux-repo.yaml` references `nuclear-vars`/`nuclear-secrets` and points paths at `./kube/clusters/nuclear/flux`. To add a cluster, copy the `biohazard` cluster dir structure and adjust cluster-name-substituted vars. Currently only `biohazard` is active.

- `kube/clusters/biohazard/flux/kustomization.yaml` — **the master kustomization**: the single list of every core component and app deployed to the cluster. Adding/removing an app requires editing this file.
- `kube/clusters/biohazard/flux/flux-repo.yaml` — root GitRepository + Kustomization containing **global patches** applied to all matching Kustomizations/HelmReleases via labelSelectors (see Labels below). Do not duplicate these patches per-app.
- `kube/deploy/apps/kustomization.yaml` — only declares the shared `apps` Namespace; individual apps are wired in via the master kustomization above.

## Secrets

**external-secrets** (runtime): pulls from 1Password via a `ClusterSecretStore` named `1p`. `ExternalSecret` resources in `kube/clusters/biohazard/config/` and per-app `vars.yaml` define what gets synced.

Never commit plaintext secrets or key material.

## Labels Drive Flux Behavior

The global patches in `flux-repo.yaml` key off labels on Kustomizations/HelmReleases. Set these on a resource to opt in/out:

| Label | Effect |
|-------|--------|
| `kustomization.flux.home.arpa/default: "false"` | Excluded from default patches |
| `kustomization.flux.home.arpa/helmpatches: "false"` | No HelmRelease patches applied |
| `wait.flux.home.arpa/disabled: "true"` | Wait disabled |
| `prune.flux.home.arpa/disabled: "true"` / `=true` | Prune disabled |
| `substitution.flux.home.arpa/disabled: "true"` | No postBuild var substitution |
| `pvc.home.arpa/volsync: "true"` | VolSync PVC dependency wiring |

HelmReleases get global defaults (interval 5m, timeout 1h, CRDs CreateReplace, remediation retries 5, driftDetection warn with `/spec/replicas` ignored). Don't re-apply these per-app unless overriding.

## PostBuild Substitution

Kustomizations receive `CLUSTER_NAME` plus vars from `biohazard-vars` and `biohazard-secrets` Secrets (synced from 1Password). Apps reference `${APP_DNS_<NAME>}`, `${APP_IP_<NAME>}`, `${APP_UID_<NAME>}`, `${CONFIG_TZ}`, etc. in their YAML — Flux substitutes these at build time.
