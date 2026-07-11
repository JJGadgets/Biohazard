# AGENTS.md

This is a GitOps homelab monorepo for a single production Kubernetes cluster ("biohazard") on Talos Linux. There is no application code to build, lint, typecheck, or test. Everything is Kubernetes YAML reconciled by Flux from this repo. Verify changes with `flux-local` (pipx) or `kustomize build`, not a test suite.

## Tooling

- `mise` installs all tools from `.mise.toml` (kubectl, flux, talosctl, helm, kustomize, yq, jq, op, etc.). Run `mise install` first.
- `task` (go-task) is the primary command interface. Root file is `Taskfile.dist.yaml`; per-domain includes live in `.taskfiles/`. Run `task` with no args to list all tasks.
- A Python venv lives at `.venv` (created by mise).
- Files are named `*.dist.yaml` (committed); local overrides drop the `.dist` segment.

## Repo Layout

- `kube/clusters/biohazard/flux/kustomization.yaml` — **the master kustomization**: this is the single list of every core component and app deployed to the cluster. Adding/removing an app requires editing this file.
- `kube/clusters/biohazard/flux/flux-repo.yaml` — root GitRepository + Kustomization containing **global patches** applied to all matching Kustomizations/HelmReleases via labelSelectors (see Labels below). Do not duplicate these patches per-app.
- `kube/deploy/core/` — cluster-essential components (networking, storage, dns, tls, ingress, monitoring, db, secrets, hardware, etc.).
- `kube/deploy/apps/<name>/` — one directory per app, each with `app/` (HelmRelease + values), `ks.yaml` (Flux Kustomization), `kustomization.yaml`, `ns.yaml`, `vars.yaml`. Most apps use the bjw-s/labs `app-template` chart.
- `kube/templates/test/` — scaffold template for new apps.
- `kube/clusters/biohazard/config/` — cluster vars + ExternalSecret manifests.
- `kube/clusters/biohazard/talos/` — talhelper config (`talconfig.yaml`) + Talos secrets.
- `kube/repos/flux/` — HelmRepository / OCIRepository sources.
- `.taskfiles/` — go-task includes per domain.
- `.renovaterc.json5` + `.renovate/` — Renovate config and presets.

## Secrets

- **external-secrets** (runtime): pulls from 1Password via a `ClusterSecretStore` named `1p`. `ExternalSecret` resources in `kube/clusters/biohazard/config/` and per-app `vars.yaml` define what gets synced.

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

## Common Tasks

```bash
task                                            # list all tasks
task talos:run C=biohazard                      # regenerate Talos config (requires `op` signed in)
task bootstrap:bootstrap C=biohazard            # full cluster bootstrap (Flux + 1Password + config)
task k8s:newapp APP=<name> IMAGENAME=<img> IMAGETAG=<tag>  # scaffold new app from template
task k8s:scale-to-0 APP=<app>                   # scale down (suspends Flux, saves replica count)
task k8s:scale-back-up APP=<app>                # restore (resumes Flux, restores replicas)
task rook:toolbox                               # Rook-Ceph toolbox shell
task pg:crunchy-master APP=<app> -- <cmd>       # exec into Crunchy Postgres primary
task flux:cantWait KS=<name> NS=flux-system      # force a stuck Kustomization to skip deps/wait
```

Task namespace aliases: `bs` (bootstrap), `f` (flux), `k` (k8s), `t` (talos), `vs` (volsync), `r` (rook), `nas` (truenas), `pl` (pulumi).

## Adding a New App

1. `task k8s:newapp APP=<name> IMAGENAME=<img> IMAGETAG=<tag>` — copies `kube/templates/test/` to `kube/deploy/apps/<name>/`, substituting `APPNAME`/`IMAGENAME`/`IMAGETAG`.
2. Edit the generated files (values, vars, resources) as needed.
3. Add the app path to `kube/clusters/biohazard/flux/kustomization.yaml`.
4. Commit and push — Flux reconciles within 5m; Renovate will track the image/chart versions.

## CI (GitHub Actions)

- **Flux Diff** — runs `flux-local` diff on PRs against `main`, posts results as PR comments. All PRs to `main` trigger this.
- **Renovate** — hourly, opens PRs for dependency updates. Most automerge. Uses semantic commits with scopes like `oci/<image>`, `helm/<chart>`, `mise/<tool>`, `gha/<action>`.
- **Flux Localhost Build** — rebuilds `kube/bootstrap/flux/flux-install-localhost-manifests.yaml` on Flux version bump, opens a PR.
- **OSTree Build** — weekly (Fri), builds and pushes OSTree images to GHCR.

## Conventions

- GitOps only: don't make imperative `kubectl apply` changes for ongoing state — everything lives in Git and is reconciled by Flux.
- `driftDetection.mode: warn` is set globally on HelmReleases; `/spec/replicas` is ignored so you can scale for debugging without Helm reverting it.
- Renovate ignorePaths: `**/archive/**`, `**/.archive/**`, `./.git`, `**/ignore/**` — do not reference `.archive/`.
- Commit signing is enabled (see `task gitconfig`).
