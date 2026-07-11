# AGENTS.md

This is JJGadgets' homelab monorepo, covering all machines in the home infrastructure. The primary focus is the "biohazard" production Kubernetes cluster on Talos Linux, reconciled by Flux from this repo. There is no application code to build, lint, typecheck, or test — everything is Kubernetes YAML, Talos config, dotfiles, and OSTree build scripts. Verify Kubernetes changes with `flux-local` (pipx) or `kustomize build`, not a test suite.

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

The repo is structured for multi-cluster. Each cluster gets its own `kube/clusters/<name>/` directory with its own `flux/kustomization.yaml` (master list) and `flux/flux-repo.yaml` (global patches). The archived `nuclear` cluster (`.archive/kube/clusters/nuclear/`) is a reference example showing the same pattern: its `flux-repo.yaml` references `nuclear-vars`/`nuclear-secrets` and points paths at `./kube/clusters/nuclear/flux`. To add a cluster, copy the `biohazard` cluster dir structure and adjust cluster-name-substituted vars. Currently only `biohazard` is active.

- `kube/clusters/biohazard/flux/kustomization.yaml` — **the master kustomization**: the single list of every core component and app deployed to the cluster. Adding/removing an app requires editing this file.
- `kube/clusters/biohazard/flux/flux-repo.yaml` — root GitRepository + Kustomization containing **global patches** applied to all matching Kustomizations/HelmReleases via labelSelectors (see Labels below). Do not duplicate these patches per-app.
- `kube/deploy/apps/kustomization.yaml` — only declares the shared `apps` Namespace; individual apps are wired in via the master kustomization above.

## Kubernetes Core Components (kube/deploy/core)

| Component | Role |
|-----------|------|
| `_networking/cilium` | CNI, kube-proxy replacement, NetworkPolicy (CiliumNetworkPolicy + CiliumClusterwideNetworkPolicy), LoadBalancer (BGP + LB-IPAM), Hubble observability, L7 proxy for DNS/FQDN policies |
| `_networking/multus` | Secondary network attachments for pods/VMs needing direct L2/VLAN access (e.g. Home Assistant to IoT VLAN) |
| `_networking/bird` | BIRD daemon for BGP/OSPF route redistribution between Cilium LB IPs and upstream router |
| `storage/rook-ceph` | HA Ceph cluster (CephFS + RBD + RGW S3), the primary distributed storage |
| `storage/democratic-csi` | Local hostpath, local XFS, and NAS ZFS (dataset + zvol) CSI drivers |
| `storage/volsync` | Backup/restore of PVCs via Restic to Cloudflare R2 and Ceph RGW |
| `storage/snapscheduler` | Scheduled CephFS/RBD volume snapshots |
| `storage/fstrim` | Periodic fstrim on Ceph OSDs |
| `storage/_external-snapshotter` + `_csi-addons` | VolumeSnapshot CRDs and Ceph CSI add-ons |
| `dns/internal/k8s-gateway` | In-cluster DNS resolution for services |
| `dns/external-dns` | Syncs DNS records to Cloudflare |
| `tls/cert-manager` + `trust-manager` | TLS certificate issuance and CA trust distribution |
| `ingress/envoy-gateway` | Gateway API controller (internal + external Gateways), ClientTrafficPolicy (TLS hardening, security headers), BackendTrafficPolicy, SecurityPolicy (forward-auth to Authentik, IP allowlists) |
| `ingress/cloudflare` | Cloudflare Tunnel for public exposure |
| `ingress/secrets-sync` | Syncs TLS secrets across namespaces for ingress |
| `ingress/stunner` | TURN/STUN for WebRTC |
| `monitoring/victoria` | VictoriaMetrics (single-node + vminsert + vmselect) |
| `monitoring/kps` | kube-prometheus-stack (Prometheus operator, alert rules, node-exporter, kube-state-metrics) |
| `monitoring/grafana` | Dashboards |
| `monitoring/alertmanager` + `karma` | Alert routing and aggregation UI |
| `monitoring/fluentbit` + `vector` | Log collection and processing pipeline |
| `monitoring/node-exporter`, `smartctl-exporter`, `intel-gpu-exporter` | Hardware metrics |
| `monitoring/keda` | Event-driven autoscaling |
| `monitoring/metrics-server` | HPA metrics |
| `db/pg` | Crunchy Postgres Operator (HA Postgres clusters with pgBackRest backups to R2 + RGW) |
| `db/redis` | Redis operator |
| `db/litestream` | Litestream for SQLite WAL replication |
| `db/mosquitto` | MQTT broker |
| `secrets/external-secrets` | Pulls secrets from 1Password via `ClusterSecretStore` named `1p` |
| `hardware/node-feature-discovery` | Labels nodes with hardware capabilities (GPU model, baremetal, etc.) |
| `hardware/intel-device-plugins` | Intel GPU / QAT device plugins |
| `hardware/nvidia` | NVIDIA GPU support (for LLM workloads) |
| `reloader` | Restarts workloads on Secret/ConfigMap changes |
| `spegel` | P2P container registry cache |
| `flux-system` | Flux healthchecks and alerting templates |

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

## Security (always first consideration)

Security is the top priority in this repo. Defense-in-depth is preferred; never complacent to old or new threats. Key measures:

- **Network policies**: CiliumNetworkPolicy (namespace-scoped) and CiliumClusterwideNetworkPolicy (cluster-scoped) define default-deny + label-based allow. Apps opt into egress by setting pod labels like `egress.home.arpa/<target>: allow` (e.g. `egress.home.arpa/internet`, `egress.home.arpa/r2`, `egress.home.arpa/github`, `egress.home.arpa/iot`, `egress.home.arpa/discord`). Ingress similarly via `ingress.home.arpa/<source>: allow`. The cluster-wide policies in `kube/deploy/core/_networking/cilium/netpols/` map each label to specific CIDRs/FQDNs/ports. FQDN-based egress uses Cilium's L7 DNS proxy (label `dns.home.arpa/l7: "true"` for per-query filtering).
- **Application authentication**: Authentik provides SSO/OIDC. Apps integrate via (1) native OIDC/OAuth2 support (`authentik.home.arpa/oidc: allow` pod label), (2) forward-auth via Envoy Gateway SecurityPolicy (component `kube/deploy/core/ingress/envoy-gateway/forward-auth/`, apps include it as a Kustomize component and set `AUTH_ROUTE`), or (3) Authentik LDAP outposts.
- **IP allowlists**: Envoy Gateway SecurityPolicy supports `authorization` rules with `clientCIDRs` for IP-based access control (e.g. OpenCode UI restricted to `IP_JJ_V4`). External Gateway adds security headers (HSTS, X-Frame-Options, nosniff, CSP-adjacent, no-referrer, FLoC block, robots noindex).
- **Runtime hardening**: `gvisor` (runsc-kvm, requires baremetal nodeSelector) and `kata` RuntimeClasses are defined in `kube/clusters/biohazard/config/gvisor.yaml`. Apps set `runtimeClassName: gvisor` or `kata` in `defaultPodOptions`. `hostUsers: false` is used where possible. All pods use `readOnlyRootFilesystem: true`, drop ALL capabilities, `seccompProfile: RuntimeDefault`, `runAsNonRoot: true`.
- **TLS hardening**: Envoy ClientTrafficPolicy enforces TLS 1.2-1.3, modern ciphers (ECDHE-ECDSA-CHACHA20-POLY1305, AES-GCM), X25519MLKEM768 post-quantum curve, mTLS client validation (optional). Ceph requires msgr2 with encryption.
- **Pod-to-pod isolation**: Apps use `networkpolicies` in their HR (app-template's built-in CiliumNetworkPolicy) for same-namespace isolation; cross-namespace traffic is via explicit labels.
- **Affinity anti-colocation**: `fuckoff.home.arpa/{{ .Release.Name }}` nodeAffinity prevents app co-location on nodes where the label exists.

## Storage Stack

### Rook-Ceph (primary HA storage)

`kube/deploy/core/storage/rook-ceph/cluster/biohazard/` — hyperconverged Ceph on Talos. 3 OSDs on Intel SSDs (encrypted), 3 MONs on control-plane nodes, 2 MGRs. CephFS has 3 data pools; RBD has block pools; RGW provides S3-compatible storage.

StorageClasses (defined in `storageclass.yaml` + HR values):
- `block` (RBD, default, 3-replica SSD, reclaim Delete) — for RWO PVCs like databases, app data needing backups.
- `block-2` (RBD, 2-replica SSD, reclaim Delete) — for RWO PVCs of non-critical data.
- `block-ssd-ec-2-1` (RBD, erasure-coded 2+1 SSD) — lower-overhead block storage.
- `file` (CephFS, 3-replica SSD data pool, reclaim Delete) — for RWX PVCs, shared data.
- `file-ec-2-1` (CephFS erasure-coded pool, reclaim Delete) — for mass non-critical RWX storage (thumbnails, caches, game server files).
- `file-size-2` (CephFS 2-replica, reclaim **Retain**) — for important mass storage (e.g. Immich library) where accidental deletion must be prevented.
- `rgw-biohazard` (RGW S3-backed) — for object storage PVCs.

### democratic-csi (local + NAS)

`kube/deploy/core/storage/democratic-csi/` — three drivers:
- `local` (local-hostpath, WaitForFirstConsumer, reclaim Delete) — for node-local single-replica PVCs like Postgres data (Crunchy default SC). No expansion support.
- `local-xfs` (local XFS hostpath, reclaim Delete, expansion supported) — fork of democratic-csi with XFS support (custom image `ghcr.io/jjgadgets/democratic-csi:xfs`).
- `nas-zfs-local-dataset` + `nas-zfs-local-zvol` (TrueNAS ZFS, nodeSelector `role.nodes.home.arpa/nas: true`, reclaim **Retain**) — for NAS-attached storage; not currently in the biohazard kustomization.

### VolSync (backups)

`kube/deploy/core/storage/volsync/template/` — template consumed by per-app `<app>-pvc` Kustomizations (label `pvc.home.arpa/volsync: "true"`). Creates a PVC (from ReplicationDestination bootstrap), two ReplicationSources: scheduled (cron `0 */12 * * *`) and on-image-update (manual trigger keyed to `VS_APP_CURRENT_VERSION`), both via Restic to Cloudflare R2. Mover pods use `egress.home.arpa/r2: allow` label. Cache uses `block` SC.

### StorageClass selection guide

- **Databases (Crunchy Postgres)**: `local` (RWO, node-local, fast) — data is backed up via pgBackRest to R2 + RGW, not VolSync.
- **App data needing backups (RWX)**: `file` (CephFS 3-replica) + VolSync — e.g. Home Assistant config, OpenClaw data.
- **App data needing backups (RWO)**: `block` (RBD 3-replica) + VolSync — e.g. OpenClaw data PVC.
- **Important mass storage (RWX, retain)**: `file-size-2` (CephFS 2-replica, Retain) — e.g. Immich library.
- **Non-critical mass storage (RWX)**: `file-ec-2-1` (CephFS erasure-coded) — e.g. thumbnails, transcode, game server files. Cheap, no backup.
- **Non-critical RWO**: `block-2` (RBD 2-replica) — e.g. OpenClaw misc (Homebrew, Nix, Go cache).
- **NAS-attached**: `nas-zfs-local-dataset`/`nas-zfs-local-zvol` — only on NAS-labelled nodes.

## Networking Stack

### Cilium (CNI + LB + NetworkPolicy)

`kube/deploy/core/_networking/cilium/` — Cilium replaces kube-proxy (kubeProxyReplacement: true), runs in native routing mode with Geneve tunnel for DSR load balancing, BGP control plane for LoadBalancer IP advertisement, IPAM multi-pool (default + ingress + vpn-vlan pools), Hubble for observability. Config is per-cluster under `app/config/<cluster>/helm-values.yaml`.

- **LoadBalancer IPs**: `CiliumLoadBalancerIPPool` resources (`loadbalancer/LB-IPs.yaml`) assign IPs from `${IP_LB_CIDR}` (public) and `${IP_LB_INTERNAL_CIDR}` (internal, label `io.cilium/internal: "true"`). Apps request specific IPs via `io.cilium/lb-ipam-ips` or `lbipam.cilium.io/ips` annotations, or `ipam.cilium.io/ip-pool` for pod-level pool assignment (e.g. OpenClaw uses `vpn-vlan` pool).
- **BGP**: `loadbalancer/BGP.yaml` — `CiliumBGPClusterConfig` peers with the FortiGate router (ASN `${ASN_ROUTER}`) and node-local BIRD (ASN `${ASN_CLUSTER_NODES}`). Advertises PodCIDR (no masquerade), CiliumPodIPPools, and LoadBalancer Service IPs.
- **NetworkPolicy**: `netpols/` contains cluster-wide default policies. `labelled-allow-egress.yaml` maps egress labels to destinations (FQDN, CIDR, entities). `labelled-allow-ingress.yaml` maps ingress labels to sources. `cluster-default-kube-dns.yaml` allows DNS to kube-dns with L7 DNS filtering for pods labelled `dns.home.arpa/l7: "true"`. `flux.yaml` allows Flux egress to world + apiserver.

### BIRD

`kube/deploy/core/_networking/bird/` — runs on each node, redistributes Cilium LB IPs (from `${IP_LB_CIDR}`) into the kernel routing table via BGP to node-local Cilium and OSPF to upstream router. This allows non-Cilium-aware hosts (FortiGate) to route to LoadBalancer IPs.

### Multus

`kube/deploy/core/_networking/multus/` — provides secondary network attachments. Networks defined under `networks/`. Apps attach via `k8s.v1.cni.cncf.io/networks` annotation specifying network name, namespace, static IP, MAC, and gateway. Used by Home Assistant (IoT VLAN), KubeVirt VMs, and others needing direct L2 access to specific VLANs.

### Envoy Gateway (Gateway API)

`kube/deploy/core/ingress/envoy-gateway/` — two GatewayClass+Gateway pairs:
- `envoy-internal` (LB IP `${APP_IP_ENVOY_INTERNAL}`) — for internal cluster access, HTTP + HTTPS listeners, all namespaces can attach HTTPRoutes. ClientTrafficPolicy enforces TLS 1.2-1.3 with post-quantum curves. BackendTrafficPolicy adds compression (Brotli/Gzip/Zstd) and custom error pages.
- `envoy-external` (LB IP `${APP_IP_ENVOY_EXTERNAL}`) — for public exposure via Cloudflare DNS (`external-dns.alpha.kubernetes.io/target: ${DNS_MAIN_CF}`). Has three listeners: http, external (HTTPS, all namespaces), public (`*.jjgadgets.tech` with dedicated cert). External ClientTrafficPolicy adds stricter security headers (noindex, no-store, X-Frame-Options, nosniff, FLoC block, Referrer-Policy). BackendTrafficPolicy has 10s request timeout + 100Ki request buffer limit.

Apps create `HTTPRoute` resources attaching to these Gateways (via `parentRefs` with `sectionName: internal`/`external`). Path-based routing and header matching are used for fine-grained control (e.g. Immich exposes only share/album paths externally).

### Forward-Auth (Authentik)

`kube/deploy/core/ingress/envoy-gateway/forward-auth/` — `SecurityPolicy` template for Envoy Gateway extAuth. Apps include this as a Kustomize component and set `AUTH_ROUTE` to their HTTPRoute name. It forwards `Cookie` header to Authentik's `/outpost.goauthentik.io/auth/envoy` endpoint, with `failOpen: false` and `recomputeRoute: true`.

### Cloudflare Tunnel

`kube/deploy/core/ingress/cloudflare/tunnel/` — Cloudflare Tunnel for public app exposure without opening firewall ports.

### Stunner

`kube/deploy/core/ingress/stunner/` — TURN/STUN server for WebRTC (e.g. for Home Assistant camera streaming).

## App Deployment Patterns

All apps use the bjw-s/labs `app-template` Helm chart (OCIRepository), deployed via Flux HelmRelease. The standard layout per app: `app/` (HelmRelease + values), `ks.yaml` (Flux Kustomizations: one for app, one for PVC, optionally one for DB), `kustomization.yaml`, `ns.yaml`, `vars.yaml` (ExternalSecret from 1Password).

### Common patterns (from app-template)

- `controllers.<name>`: deployment or statefulset, with `replicas`, `strategy`, `pod.labels` (for netpol opt-in), `pod.annotations` (for Multus/IPAM), `pod.runtimeClassName`.
- `securityContext`: `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`.
- `defaultPodOptions.securityContext`: `runAsNonRoot: true`, `runAsUser`/`runAsGroup`/`fsGroup` (app-specific UID), `seccompProfile: RuntimeDefault`, `fsGroupChangePolicy`.
- `defaultPodOptions.affinity.nodeAffinity`: `fuckoff.home.arpa/{{ .Release.Name }}` DoesNotExist (anti-colocation).
- `defaultPodOptions.hostAliases`: Authentik host alias (`${APP_IP_AUTHENTIK}` → `${APP_DNS_AUTHENTIK}`) for OIDC apps.
- `defaultPodOptions.dnsConfig.options`: `ndots: "1"` (reduces DNS search path recursion).
- `defaultPodOptions.automountServiceAccountToken: false`, `enableServiceLinks: false`.
- `persistence`: `existingClaim` for app data, `emptyDir` (medium: Memory) for tmp, optional `configMap`/`secret` mounts.
- `route`: HTTPRoute to `envoy-internal` (sectionName: internal) and optionally `envoy-external` (sectionName: external).
- `service`: primary HTTP service + optional LoadBalancer `expose` service (for non-HTTP ports like LDAP, RADIUS, game servers, HomeKit).
- `networkpolicies`: built-in CiliumNetworkPolicy for same-namespace isolation.
- `serviceMonitor`: for Prometheus metrics scraping.
- `probes`: liveness + readiness, sometimes startup (for slow-starting apps).

### PVC pattern

Apps that need persistent storage create a separate `<app>-pvc` Flux Kustomization (label `pvc.home.arpa/volsync: "true"`) pointing at the VolSync template (`kube/deploy/core/storage/volsync/template`). It substitutes PVC name, size, SC, access modes, app UID/GID, and `VS_APP_CURRENT_VERSION` (the app's image ref, used as a manual backup trigger on image updates). The app's main Kustomization `dependsOn` the PVC Kustomization. Some apps also define a separate `<app>-misc` PVC directly in `app/pvc.yaml` (e.g. for caches, transcode) — these use cheaper SCs (`file-ec-2-1`, `block-2`) and are labelled `kustomize.toolkit.fluxcd.io/prune: Disabled`.

### DB pattern

Apps needing Postgres create a `<app>-db` Kustomization pointing at the Crunchy template (`kube/deploy/core/db/pg/clusters/template`) or the pguser template. It substitutes PG name, namespace, DB/user, replicas, SC (typically `local`), size, config version. The app's HR references the generated `pg-<name>-pguser-<user>` Secret for DB credentials. Backups go to R2 (repo2) + RGW (repo3) via pgBackRest.

### App examples and nuances

**Immich** (`kube/deploy/apps/immich/`): Multi-controller (server 2 replicas, microservices 2 replicas, ML 3 replicas with OpenVINO + Intel GPU, Redis, cronjob for ML model preloading from HuggingFace). Uses `file-size-2` SC (Retain) for the 700Gi library (important mass storage), `file-ec-2-1` for misc (thumbnails, encoded video — regenerable). External HTTPRoute only exposes `/s/`, `/share/`, `/_app/immutable/`, `/api/shared-links/` etc. with shared-link-cookie header matching — not the full app. GPU via `supplementalGroups: [44]` + `gpu.intel.com/i915: "1"` resource limit. ML model pull cronjobs use `egress.home.arpa/internet: allow`. Uses `pg-home` (shared home Postgres cluster), not its own. Pod labels: `authentik.home.arpa/oidc: allow` for OIDC auth.

**Authentik** (`kube/deploy/apps/authentik/`): Multi-controller (server 2 replicas, worker 2 replicas, LDAP outpost 2 replicas, RADIUS 2 replicas, RAC 2 replicas). `runtimeClassName: gvisor` on all pods. Server exposes HTTP (9000) + HTTPS (9443) + metrics (9300). LoadBalancer services for LDAP (389/636 TCP+UDP) and RADIUS (1812 TCP+UDP) with dedicated LB IPs + CoreDNS hostnames. External HTTPRoute has a `harden` route that redirects `/if/admin`, `/api/v3/policies/expression`, `/api/v3/propertymappings`, `/api/v3/managed/blueprints` to google.com (security through obscurity for admin paths). A `forward-auth` HTTPRoute handles `/outpost.goauthentik.io` paths on both internal and external Gateways. Uses its own `pg-authentik` Crunchy cluster. Media stored on S3 (RGW). Complex CiliumNetworkPolicy: ingress allows by `authentik.home.arpa/http`/`https`/`oidc` labels with TLS termination rules; egress to Duo, Plex, HIBP, AWS SES, S3 — all FQDN-based with DNS proxy rules. ClusterwideNetworkPolicies map those labels for egress from other namespaces.

**OpenClaw** (`kube/deploy/apps/openclaw/`): Two containers in one pod (OpenClaw + OpenCode web UI). `runtimeClassName: gvisor`. Pod IPAM annotation `ipam.cilium.io/ip-pool: vpn-vlan` for VPN egress. Data PVC uses `block` SC (10Gi, RWO, backed up via VolSync). Misc PVC uses `block-2` (50Gi, RWO, not backed up — Homebrew, Nix, Go cache). Includes forward-auth component (`AUTH_ROUTE: openclaw-app`). OpenCode UI has a separate `SecurityPolicy` (`envoy.yaml`) with IP allowlist (`IP_JJ_V4`). RBAC: Role for `pods/exec` + `deployments` patch (for LLM deploy), ClusterRoleBinding to `view` (read-only cluster access). Netpol allows egress to llama-cpp, searxng, soft-serve namespaces + FQDNs (brew.sh, openrouter.ai, nvidia.com, openai.com, chatgpt.com, etc.). Has an initContainer that blocks until OpenClaw is set up. `automountServiceAccountToken: true` (needed for k8s API access).

**Home Assistant** (`kube/deploy/apps/home-assistant/`): Single replica. Multus annotation attaches to `iot` network with static IP + MAC + gateway for direct IoT VLAN access. Egress labels: `egress.home.arpa/iot`, `esp`, `appletv`, `r2`, `pypi`, `github` (HACS), `db.home.arpa/mqtt`. LoadBalancer service for HomeKit (ports 21061-21066). Data PVC `file` SC (10Gi, RWX, VolSync backup). `runtimeClassName: gvisor`. `runAsUser: 65534` (nobody) due to image's uv workaround. Startup probe with `failureThreshold: 3600` (slow DB migrations). Authentik OIDC via `authentik.home.arpa/oidc: allow` label + hostAliases. No netpol in HR (relies on cluster-wide policies + the Multus interface for IoT VLAN isolation).

**Plex** (`kube/deploy/apps/media/plex/`): In `media` namespace (shared with other media apps). LoadBalancer service (not HTTPRoute-only) for media streaming on port 32400. Data PVC `file` SC (50Gi, RWX, VolSync). Misc PVC `file-ec-2-1` (100Gi, cache + transcode — regenerable). Mounts shared `media-data` and `media-bulk` PVCs (read-only) for media library. Intel GPU via `gpu.intel.com/i915: "1"` + `supplementalGroups: [44]`. Preferred nodeAffinity for specific GPU models (12600H > 8500T > 8100T). External HTTPRoute removes `Range` header on `/library/streams` to prevent seeking abuse. Netpol allows ingress from Home Assistant namespace on port 32400. No gvisor (needs GPU + host access for transcoding). `automountServiceAccountToken: false`.

**Insurgency Sandstorm** (`kube/deploy/apps/insurgency-sandstorm/`): Game server. `runtimeClassName: kata` (Kata containers, not gvisor — different isolation). `hostUsers: false`. LoadBalancer service with UDP ports (game 27102, query 27131) + CoreDNS hostname. Data PVC `file-ec-2-1` (20Gi, RWX — game files are redownloadable, labelled as such). Config from ConfigMaps (Game.ini, Engine.ini, MapCycle, Mods), secrets mounted as files (GameUserSettings, Admins). A daily cronjob downloads/updates game files via steamcmd (uses `egress.home.arpa/internet: allow`, `readOnlyRootFilesystem: false` for that cronjob only). Netpol: CiliumNetworkPolicy with FQDN egress to `*.mod.io`, `*.modapi.io`, `*.modcdn.io` for mod downloads. Ingress label `ingress.home.arpa/world: allow` (game server must be reachable from internet). Preferred nodeAffinity for `dorothy` (MS01, no etcd/Ceph contention). No probes (UDP probes don't work). KEDA ScaledObject (commented out) would scale to 0 based on Hubble flow metrics.

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
2. Edit the generated files: set pod labels for netpol/ingress/auth opt-in, runtimeClassName, securityContext UID/GID, persistence (create `<app>-pvc` Kustomization for VolSync-backed PVC or inline PVC for misc), route (internal/external Gateway refs), service (LB if non-HTTP ports), optionally DB Kustomization.
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
- All network access is default-deny; apps must explicitly label pods for every egress/ingress path they need.
- Prefer defense-in-depth: gvisor/kata runtime isolation + CiliumNetworkPolicy + Authentik auth + TLS hardening + security headers.
- App images are pinned with digests (`image.tag: version@sha256:...`); Renovate updates them.
- The `app-template` chart version is set per-app via `postBuild.substitute.APP_TEMPLATE` in `ks.yaml`, not globally.
