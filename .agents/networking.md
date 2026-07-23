# Networking Stack

## Cilium (CNI + LB + NetworkPolicy)

`kube/deploy/core/_networking/cilium/` — Cilium replaces kube-proxy (kubeProxyReplacement: true), runs in native routing mode with Geneve tunnel for DSR load balancing, BGP control plane for LoadBalancer IP advertisement, IPAM multi-pool (default + ingress + vpn-vlan pools), Hubble for observability. Config is per-cluster under `app/config/<cluster>/helm-values.yaml`.

- **LoadBalancer IPs**: `CiliumLoadBalancerIPPool` resources (`loadbalancer/LB-IPs.yaml`) assign IPs from `${IP_LB_CIDR}` (public) and `${IP_LB_INTERNAL_CIDR}` (internal, label `io.cilium/internal: "true"`). Apps request specific IPs via `io.cilium/lb-ipam-ips` or `lbipam.cilium.io/ips` annotations, or `ipam.cilium.io/ip-pool` for pod-level pool assignment (e.g. OpenClaw uses `vpn-vlan` pool).
- **BGP**: `loadbalancer/BGP.yaml` — `CiliumBGPClusterConfig` peers with the FortiGate router (ASN `${ASN_ROUTER}`) and node-local BIRD (ASN `${ASN_CLUSTER_NODES}`). Advertises PodCIDR (no masquerade), CiliumPodIPPools, and LoadBalancer Service IPs.
- **NetworkPolicy**: `netpols/` contains cluster-wide default policies. `labelled-allow-egress.yaml` maps egress labels to destinations (FQDN, CIDR, entities). `labelled-allow-ingress.yaml` maps ingress labels to sources. `cluster-default-kube-dns.yaml` allows DNS to kube-dns with L7 DNS filtering for pods labelled `dns.home.arpa/l7: "true"`. `flux.yaml` allows Flux egress to world + apiserver.

## BIRD

`kube/deploy/core/_networking/bird/` — runs on each node, redistributes Cilium LB IPs (from `${IP_LB_CIDR}`) into the kernel routing table via BGP to node-local Cilium and OSPF to upstream router. This allows older L3 switches that don't speak BGP to route to LoadBalancer IPs. The FortiGate router does not need BIRD — it peers with Cilium directly via BGP.

## Multus

`kube/deploy/core/_networking/multus/` — provides secondary network attachments. Networks defined under `networks/`. Apps attach via `k8s.v1.cni.cncf.io/networks` annotation specifying network name, namespace, static IP, MAC, and gateway. Used by Home Assistant (IoT VLAN), KubeVirt VMs, and others needing direct L2 access to specific VLANs.

## Envoy Gateway (Gateway API)

`kube/deploy/core/ingress/envoy-gateway/` — two GatewayClass+Gateway pairs:
- `envoy-internal` (LB IP `${APP_IP_ENVOY_INTERNAL}`) — for internal cluster access, HTTP + HTTPS listeners, all namespaces can attach HTTPRoutes. ClientTrafficPolicy enforces TLS 1.2-1.3 with post-quantum curves. BackendTrafficPolicy adds compression (Brotli/Gzip/Zstd) and custom error pages.
- `envoy-external` (LB IP `${APP_IP_ENVOY_EXTERNAL}`) — for public exposure via Cloudflare DNS (`external-dns.alpha.kubernetes.io/target: ${DNS_MAIN_CF}`). Has three listeners: http, external (HTTPS, all namespaces), public (`*.jjgadgets.tech` with dedicated cert). External ClientTrafficPolicy adds stricter security headers (noindex, no-store, X-Frame-Options, nosniff, FLoC block, Referrer-Policy). BackendTrafficPolicy has 10s request timeout + 100Ki request buffer limit.

Apps create `HTTPRoute` resources attaching to these Gateways (via `parentRefs` with `sectionName: internal`/`external`). Path-based routing and header matching are used for fine-grained control (e.g. Immich exposes only share/album paths externally).

## Forward-Auth (Authentik)

`kube/deploy/core/ingress/envoy-gateway/forward-auth/` — `SecurityPolicy` template for Envoy Gateway extAuth. Apps include this as a Kustomize component and set `AUTH_ROUTE` to their HTTPRoute name. It forwards `Cookie` header to Authentik's `/outpost.goauthentik.io/auth/envoy` endpoint, with `failOpen: false` and `recomputeRoute: true`.

## Cloudflare Tunnel

`kube/deploy/core/ingress/cloudflare/tunnel/` — Cloudflare Tunnel for public app exposure without opening firewall ports.

## Stunner

`kube/deploy/core/ingress/stunner/` — TURN/STUN server for WebRTC (e.g. for Home Assistant camera streaming).
