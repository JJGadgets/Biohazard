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

Security is the top priority in this repo. The following security principles guide all infrastructure and application design decisions. Each principle maps to concrete measures implemented across the cluster.

### Defense in Depth

Multiple independent security layers protect the cluster so that no single layer failure compromises the whole. If one control is bypassed or misconfigured, others continue to enforce protection. The layered approach combines:

- **Network layer**: Cilium default-deny network policies (CiliumNetworkPolicy at namespace scope + CiliumClusterwideNetworkPolicy at cluster scope)
- **Runtime layer**: gvisor (runsc-kvm) and kata container isolation — workloads run inside sandboxed environments separate from the host kernel
- **Identity layer**: Authentik SSO/OIDC authentication gates access to all applications
- **Transport layer**: TLS 1.2-1.3 with post-quantum key exchange curves, optional mTLS client validation
- **Header layer**: Security headers on external gateways (HSTS, X-Frame-Options, nosniff, CSP-adjacent, no-referrer, FLoC block, robots noindex)

### Principle of Least Privilege

Every workload receives only the minimum permissions, network access, and filesystem access required to function — nothing more.

- **Linux capabilities**: ALL capabilities dropped on every pod; `allowPrivilegeEscalation: false`
- **Filesystem**: `readOnlyRootFilesystem: true` on all pods; writes only to explicitly mounted volumes
- **Syscalls**: `seccompProfile: RuntimeDefault` restricts the system call surface to the default profile
- **Network**: Default-deny — apps must explicitly label every egress/ingress path they need via `egress.home.arpa/<target>: allow` and `ingress.home.arpa/<source>: allow` pod labels
- **Service accounts**: `automountServiceAccountToken: false` by default; RBAC roles scoped to exact permissions needed (e.g. OpenClaw gets `view` ClusterRole for read-only cluster access + a specific Role for only `pods/exec` and `deployments` patch)
- **Host access**: `hostUsers: false` where possible; no host namespaces or host path mounts unless absolutely required by the workload (e.g. GPU transcoding)

### Default Deny (Deny-by-Default)

All network access is denied unless explicitly allowed. Nothing is reachable by default — access must be opted into.

- CiliumNetworkPolicy and CiliumClusterwideNetworkPolicy implement default-deny at both namespace and cluster scope
- Apps opt into egress via `egress.home.arpa/<target>: allow` pod labels (e.g. `internet`, `r2`, `github`, `iot`, `discord`); the cluster-wide policies in `kube/deploy/core/_networking/cilium/netpols/` map each label to specific CIDRs/FQDNs/ports
- Apps opt into ingress via `ingress.home.arpa/<source>: allow` pod labels
- FQDN-based egress uses Cilium's L7 DNS proxy (`dns.home.arpa/l7: "true"` for per-query filtering, not just IP-level allow)
- No app is exposed externally or publicly unless explicitly stated; VPN access is preferred over exposing apps

### Zero Trust

No implicit trust is granted based on network location, pod identity, or namespace proximity. Every access request is authenticated and authorized.

- Application access requires authentication via Authentik — apps integrate via (1) native OIDC/OAuth2 (`authentik.home.arpa/oidc: allow` pod label), (2) forward-auth via Envoy Gateway SecurityPolicy, or (3) Authentik LDAP outposts
- Sensitive UIs restricted by IP allowlists (Envoy SecurityPolicy `authorization` rules with `clientCIDRs`, e.g. OpenCode UI restricted to `IP_JJ_V4`)
- Pod-to-pod isolation within the same namespace via app-template's built-in Kubernetes NetworkPolicy
- Cross-namespace traffic requires explicit label-based allow rules — no implicit namespace trust

### Encryption Everywhere

All data in transit is encrypted using modern, hardened protocols. No plaintext protocols are used for cluster communication.

- Envoy ClientTrafficPolicy enforces TLS 1.2-1.3 with modern ciphers (ECDHE-ECDSA-CHACHA20-POLY1305, AES-GCM)
- X25519MLKEM768 post-quantum key exchange curve for forward secrecy against quantum adversaries
- Optional mTLS client validation for additional identity verification
- Ceph inter-daemon communication encrypted via msgr2 with encryption

### Secret Hygiene

Secrets and sensitive values are never committed in plaintext. Treating infrastructure metadata as secrets prevents probing, enumeration, and network mapping by adversaries.

- 1Password is the single source of truth for all secrets; ExternalSecrets syncs at runtime via `ClusterSecretStore` named `1p`
- `APP_*` variables (`${APP_DNS_<NAME>}`, `${APP_IP_<NAME>}`, `${APP_UID_<NAME>}`, `${APP_MAC_<NAME>}`, per-protocol variants like `${APP_DNS_<NAME>_<PROTOCOL>}`) are cluster-specific and stored in 1Password, surfaced via ExternalSecret — never committed in plaintext
- Never commit plaintext secrets or key material

### Attack Surface Minimization

Exposure is reduced wherever possible — the smallest viable surface is exposed, and only to the smallest viable audience.

- Path-based external routing restricts what's publicly accessible (e.g. Immich only exposes `/s/`, `/share/`, `/_app/immutable/` paths externally, not the full app)
- Security headers prevent clickjacking (X-Frame-Options), MIME sniffing (nosniff), referrer leaks (no-referrer), FLoC tracking (FLoC block), and search engine indexing (noindex)
- Admin paths obscured (e.g. Authentik redirects `/if/admin`, `/api/v3/policies/expression`, `/api/v3/propertymappings`, `/api/v3/managed/blueprints` to an external site)
- No default external exposure — apps are internal-only unless explicitly required

### Secure by Default

Hardening is baked into the app template defaults, not opt-in. New apps inherit these protections automatically.

- `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile: RuntimeDefault`, `runAsNonRoot: true` are defaults in all app HelmReleases
- `enableServiceLinks: false` and `automountServiceAccountToken: false` by default
- Runtime isolation (`runtimeClassName: gvisor` or `kata`) used wherever compatible with workload requirements
- `dnsConfig.options: ndots: "1"` to reduce DNS search path recursion

### Supply Chain & Vulnerability Management

- All container images pinned with digests (`image.tag: version@sha256:...`); Renovate automates version and digest updates
- Always use latest versions of software (Agent Rule 3); always pin all versions including digests/hashes (Agent Rule 4)
- Security audit required after completing any work, regardless of severity (Agent Rule 8); fixes in a separate commit for clarity
- Vulnerability disclosure process for pushed/released vulnerable code (Agent Rule 9) — CVSS v3 scoring, auto-published to forge issues for `JJGadgets`/`ciel-shieru` repos

See [`.agents/security.md`](.agents/security.md) for full implementation details of each concrete measure.

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
