# Kubernetes Core Components (kube/deploy/core)

| Component | Role |
|-----------|------|
| `_networking/cilium` | CNI, kube-proxy replacement, NetworkPolicy (CiliumNetworkPolicy + CiliumClusterwideNetworkPolicy), LoadBalancer (BGP + LB-IPAM), Hubble observability, L7 proxy for DNS/FQDN policies |
| `_networking/multus` | Secondary network attachments for pods/VMs needing direct L2/VLAN access (e.g. Home Assistant to IoT VLAN) |
| `_networking/bird` | BIRD daemon for advertising Cilium LB IP routes to older L3 switches that don't speak BGP (FortiGate already peers with Cilium directly) |
| `storage/rook-ceph` | HA Ceph cluster (CephFS + RBD + RGW S3), the primary distributed storage |
| `storage/democratic-csi` | Local hostpath, local XFS, and NAS ZFS (dataset + zvol) CSI drivers |
| `storage/volsync` | Backup/restore of PVCs via Restic to Cloudflare R2 and Ceph RGW |
| `storage/snapscheduler` | Scheduled CephFS/RBD volume snapshots |
| `storage/fstrim` | Periodic fstrim on Ceph OSDs |
| `storage/_external-snapshotter` + `_csi-addons` | VolumeSnapshot CRDs and Ceph CSI add-ons |
| `dns/internal/k8s-gateway` | In-cluster DNS resolution for services; FortiGate's DNS server forwards cluster-domain queries here for all home network clients including VPN users |
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
