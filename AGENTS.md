# AGENTS.md

This is JJGadgets' homelab monorepo, covering all machines in the home infrastructure. The primary focus is the "biohazard" production Kubernetes cluster on Talos Linux, reconciled by Flux from this repo. There is no application code to build, lint, typecheck, or test — everything is Kubernetes YAML, Talos config, dotfiles, and OSTree build scripts. Verify Kubernetes changes with `flux-local` (pipx) or `kustomize build`, not a test suite.

This is a personal "production" environment used to explore security solutions and infrastructure patterns in a real-world setting. "Glorifying jank that *works*" is the operating philosophy.

## Agent Rules

All agents must follow these rules:

1. Before writing any code, or when you are stuck, or when you are unable to troubleshoot, you are highly recommended to use web search and web fetch, check Kubesearch.dev, and check source code repositories like GitHub for relevant code or information, to research and understand anything and everything you are unsure of or have doubts about.

2. Always version control all changes with Git with semantic commits.

3. Always check for the latest versions of any software with web search and web fetch, and always use the latest versions.

4. Always pin all software versions, including adding digests/hashes.

5. Always use subagents to build code, but avoid parallelism with subagents.

6. Security should always be the first cosideration.

7. Always write code adhering to secure coding practices.

8. Always security audit your work after completing for any potential security issues regardless of severity and fix them in a separate commit or change for clarity.

9. If vulnerable code has already been pushed to the Git remote (e.g. GitHub) and a release has been cut with the vulnerable commit, document the vulnerability clearly in a vulnerability disclosure format with the appropriate risk scoring (e.g. CVSS v3) and resultant severity. If the Git owner is "JJGadgets" or "ciel-shieru", publish the vulnerability documentation automatically in a forge issue (e.g. GitHub Issues, Forgejo Issues) and in the repo docs, else store it locally for user to manually publish.

## Tooling

- `mise` installs all tools from `.mise.toml` (kubectl, flux, talosctl, helm, kustomize, yq, jq, op, etc.). Run `mise install` first.
- `task` (go-task) is the primary command interface. Root file is `Taskfile.dist.yaml`; per-domain includes live in `.taskfiles/`. Run `task` with no args to list all tasks.
- A Python venv lives at `.venv` (created by mise).
- Files are named `*.dist.yaml` (committed); local overrides drop the `.dist` segment.

## Repo Layout

```
kube/
├── clusters/<cluster>/          # one dir per cluster, multi-cluster-ready
│   ├── flux/
│   │   ├── kustomization.yaml   # MASTER list of everything deployed to that cluster
│   │   ├── flux-repo.yaml       # GitRepository + root Kustomization with global patches
│   │   └── externalsecret.yaml
│   ├── config/                  # cluster vars + ExternalSecret manifests
│   └── talos/                   # talhelper talconfig.yaml + Talos secrets
├── deploy/
│   ├── core/                    # cluster-essential components
│   └── apps/<name>/             # one dir per app
├── repos/flux/                  # HelmRepository / OCIRepository sources
└── templates/test/              # scaffold template for new apps
.taskfiles/                      # go-task includes per domain
.renovaterc.json5 + .renovate/    # Renovate config and presets
ostree/                          # rpm-ostree host image build (outside k8s)
dots/                            # dotfiles (k9s, nvim, starship, etc.)
```

## Multi-Cluster

The repo is structured for multi-cluster. Each cluster gets its own `kube/clusters/<name>/` directory with its own `flux/kustomization.yaml` (master list) and `flux/flux-repo.yaml` (global patches). Currently only `biohazard` is active. See [`.agents/flux.md`](.agents/flux.md) for full details on multi-cluster setup, Flux labels, PostBuild substitution, and secrets management.

Key files:
- `kube/clusters/biohazard/flux/kustomization.yaml` — **the master kustomization**: the single list of every core component and app deployed to the cluster. Adding/removing an app requires editing this file.
- `kube/clusters/biohazard/flux/flux-repo.yaml` — root GitRepository + Kustomization containing **global patches** applied to all matching Kustomizations/HelmReleases via labelSelectors. Do not duplicate these patches per-app.
- `kube/deploy/apps/kustomization.yaml` — only declares the shared `apps` Namespace; individual apps are wired in via the master kustomization above.

## Security (always first consideration)

Security is the top priority in this repo. Nine principles guide all infrastructure and application design decisions:

- **Defense in Depth** — Multiple independent layers (network, runtime, identity, transport, header) so no single failure compromises the whole.
- **Principle of Least Privilege** — Minimum permissions only: ALL capabilities dropped, read-only root fs, seccomp default, default-deny network, scoped RBAC, no host access.
- **Default Deny** — All network access denied unless explicitly allowed via Cilium label-based opt-in (`egress.home.arpa/<target>: allow`, `ingress.home.arpa/<source>: allow`); no default external exposure.
- **Zero Trust** — No implicit trust by location or identity; Authentik SSO/OIDC auth on all apps, IP allowlists on sensitive UIs, explicit cross-namespace isolation.
- **Encryption Everywhere** — TLS 1.2-1.3 with post-quantum key exchange (X25519MLKEM768), optional mTLS, Ceph msgr2 encryption; no plaintext protocols.
- **Secret Hygiene** — 1Password is the single source of truth via ExternalSecrets; `APP_*` variables treated as secrets to prevent probing and enumeration; never commit plaintext.
- **Attack Surface Minimization** — Path-based external routing, security headers, admin path obscurity; smallest viable surface to smallest viable audience.
- **Secure by Default** — Hardening baked into app-template defaults (read-only fs, cap drop, seccomp, non-root, no SA token, gvisor/kata runtime); new apps inherit automatically.
- **Supply Chain & Vulnerability Management** — All images pinned with digests, Renovate auto-updates, mandatory security audits, CVSS v3 vulnerability disclosure process.

See [`.agents/security.md`](.agents/security.md) for full principles explanation and concrete implementation details.

## Conventions

- GitOps only: don't make imperative `kubectl apply` changes for ongoing state — everything lives in Git and is reconciled by Flux.
- `driftDetection.mode: warn` is set globally on HelmReleases; `/spec/replicas` is ignored so you can scale for debugging without Helm reverting it.
- Renovate ignorePaths: `**/archive/**`, `**/.archive/**`, `./.git`, `**/ignore/**` — do not reference `.archive/`.
- Commit signing is enabled (see `task gitconfig`).
- All network access is default-deny; apps must explicitly label pods for every egress/ingress path they need.
- Prefer defense-in-depth: gvisor/kata runtime isolation + CiliumNetworkPolicy + Authentik auth + TLS hardening + security headers.
- App images are pinned with digests (`image.tag: version@sha256:...`); Renovate updates them.

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

## Detailed Topics

Detailed documentation is split across topic files under `.agents/`:

| File | Topic |
|------|-------|
| [`.agents/flux.md`](.agents/flux.md) | Multi-cluster setup, Flux labels, PostBuild substitution, secrets management |
| [`.agents/core-components.md`](.agents/core-components.md) | Kubernetes core components reference table |
| [`.agents/security.md`](.agents/security.md) | Security practices and defense-in-depth measures |
| [`.agents/storage.md`](.agents/storage.md) | Storage stack (Rook-Ceph, democratic-csi, VolSync, StorageClass guide) |
| [`.agents/networking.md`](.agents/networking.md) | Networking stack (Cilium, BIRD, Multus, Envoy Gateway, Cloudflare, Stunner) |
| [`.agents/app-deployment.md`](.agents/app-deployment.md) | App deployment patterns, PVC/DB patterns, app examples |
| [`.agents/new-app.md`](.agents/new-app.md) | Step-by-step guide for adding a new app |
| [`.agents/ci.md`](.agents/ci.md) | CI/CD (GitHub Actions) |
