# Security (always first consideration)

Security is the top priority in this repo. The following security principles (non-exhaustive) guide all infrastructure and application design decisions. Each principle maps to concrete measures implemented across the cluster. Security posture should always be continuously improved and adaptable to both old and emerging threats.

## Security Principles

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

## Concrete Measures

Key implementation details (file paths, label names, specific configurations):

- **Network policies**: CiliumNetworkPolicy (namespace-scoped) and CiliumClusterwideNetworkPolicy (cluster-scoped) define default-deny + label-based allow. Apps opt into egress by setting pod labels like `egress.home.arpa/<target>: allow` (e.g. `egress.home.arpa/internet`, `egress.home.arpa/r2`, `egress.home.arpa/github`, `egress.home.arpa/iot`, `egress.home.arpa/discord`). Ingress similarly via `ingress.home.arpa/<source>: allow`. The cluster-wide policies in `kube/deploy/core/_networking/cilium/netpols/` map each label to specific CIDRs/FQDNs/ports. FQDN-based egress uses Cilium's L7 DNS proxy (label `dns.home.arpa/l7: "true"` for per-query filtering).
- **Application authentication**: Authentik provides SSO/OIDC. Apps integrate via (1) native OIDC/OAuth2 support (`authentik.home.arpa/oidc: allow` pod label), (2) forward-auth via Envoy Gateway SecurityPolicy (component `kube/deploy/core/ingress/envoy-gateway/forward-auth/`, apps include it as a Kustomize component and set `AUTH_ROUTE`), or (3) Authentik LDAP outposts.
- **IP allowlists**: Envoy Gateway SecurityPolicy supports `authorization` rules with `clientCIDRs` for IP-based access control (e.g. OpenCode UI restricted to `IP_JJ_V4`). External Gateway adds security headers (HSTS, X-Frame-Options, nosniff, CSP-adjacent, no-referrer, FLoC block, robots noindex).
- **Runtime hardening**: `gvisor` (runsc-kvm, requires baremetal nodeSelector) and `kata` RuntimeClasses are defined in `kube/clusters/biohazard/config/gvisor.yaml`. Apps set `runtimeClassName: gvisor` or `kata` in `defaultPodOptions`. `hostUsers: false` is used where possible. All pods use `readOnlyRootFilesystem: true`, drop ALL capabilities, `seccompProfile: RuntimeDefault`, `runAsNonRoot: true`.
- **TLS hardening**: Envoy ClientTrafficPolicy enforces TLS 1.2-1.3, modern ciphers (ECDHE-ECDSA-CHACHA20-POLY1305, AES-GCM), X25519MLKEM768 post-quantum curve, mTLS client validation (optional). Ceph requires msgr2 with encryption.
- **Pod-to-pod isolation**: Apps use `networkpolicies` in their HR (app-template's built-in Kubernetes NetworkPolicy) for same-namespace isolation; cross-namespace traffic is via explicit labels.
- **No default external exposure**: Apps must never be exposed externally or publicly unless explicitly stated. VPN access is preferred over exposing apps.
- **`APP_*` variables**: Substituted values like `${APP_DNS_<NAME>}` (internal DNS hostname), `${APP_IP_<NAME>}` (LoadBalancer/internal IP), `${APP_UID_<NAME>}` (container UID/GID), `${APP_MAC_<NAME>}` (Multus MAC), `${APP_DNS_<NAME>_<PROTOCOL>}` / `${APP_IP_<NAME>_<PROTOCOL>}` (per-protocol e.g. LDAP/RADIUS) are cluster-specific and must never be committed in plaintext — store them in 1Password and surface via ExternalSecret. Treating them as secrets prevents probing, enumeration, and network mapping by bad actors.
