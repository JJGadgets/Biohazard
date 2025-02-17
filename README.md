# Biohazard - JJ's Homelab Monorepo

**<ins>Glorifying jank that *works*.</ins>**

Powered by Flux, Kubernetes, Cilium, Talos, and jank. Amongst others.

<!--![Biohazard - CPU](https://img.shields.io/endpoint?url=https%3A%2F%2Fbiohazard-metrics.jjgadgets.tech%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_cpu_usage&style=flat&label=Biohazard%20-%20CPU)
![Biohazard - Memory](https://img.shields.io/endpoint?url=https%3A%2F%2Fbiohazard-metrics.jjgadgets.tech%2Fquery%3Fformat%3Dendpoint%26metric%3Dcluster_memory_usage&style=flat&label=Biohazard%20-%20Memory)
![Blackhawk - Battery Charge](https://img.shields.io/endpoint?url=https%3A%2F%2Fbiohazard-metrics.jjgadgets.tech%2Fquery%3Fformat%3Dendpoint%26metric%3Dblackhawk_battery_percent&style=flat&label=Blackhawk%20-%20Battery%20Charge&link=https%3A%2F%2Fgithub.com%2Fkashalls%2Fkromgo)
![Blackhawk - Battery Health](https://img.shields.io/endpoint?url=https%3A%2F%2Fbiohazard-metrics.jjgadgets.tech%2Fquery%3Fformat%3Dendpoint%26metric%3Dblackhawk_battery_health&style=flat&label=Blackhawk%20-%20Battery%20Health&link=https%3A%2F%2Fgithub.com%2Fkashalls%2Fkromgo)
![Blackhawk - Battery Cycles](https://img.shields.io/endpoint?url=https%3A%2F%2Fbiohazard-metrics.jjgadgets.tech%2Fquery%3Fformat%3Dendpoint%26metric%3Dblackhawk_battery_cycles&style=flat&label=Blackhawk%20-%20Battery%20Health&link=https%3A%2F%2Fgithub.com%2Fkashalls%2Fkromgo)-->
<div align="center">

![Biohazard - Talos](https://biohazard-metrics.jjgadgets.tech/talos_build_version?format=badge)
![Biohazard - Kubernetes](https://biohazard-metrics.jjgadgets.tech/kubernetes_build_version?format=badge)
![Biohazard - Cilium](https://biohazard-metrics.jjgadgets.tech/cilium_version?format=badge)
<br><br>
![Biohazard - CPU](https://biohazard-metrics.jjgadgets.tech/cluster_cpu_usage?format=badge)
![Biohazard - Memory](https://biohazard-metrics.jjgadgets.tech/cluster_memory_usage?format=badge)
![Biohazard - Net TX](https://biohazard-metrics.jjgadgets.tech/cluster_network_transmit_usage?format=badge)
![Biohazard - Net RX](https://biohazard-metrics.jjgadgets.tech/cluster_network_receive_usage?format=badge)
<br><br>
![Biohazard - Cluster Age](https://biohazard-metrics.jjgadgets.tech/cluster_age_days?format=badge)
![Biohazard - Uptime](https://biohazard-metrics.jjgadgets.tech/cluster_uptime_days?format=badge)
![Biohazard - Nodes](https://biohazard-metrics.jjgadgets.tech/cluster_node_count?format=badge)
![Biohazard - Pods Running](https://biohazard-metrics.jjgadgets.tech/cluster_pods_running?format=badge)
![Biohazard - Pods Unhealthy](https://biohazard-metrics.jjgadgets.tech/cluster_pods_unhealthy?format=badge)
![Biohazard - Active Alerts](https://biohazard-metrics.jjgadgets.tech/prometheus_active_alerts?format=badge)
![Biohazard - Cilium Endpoints Unhealthy](https://biohazard-metrics.jjgadgets.tech/cilium_endpoints_unhealthy?format=badge)
![Biohazard - Cilium BPF Map Pressure](https://biohazard-metrics.jjgadgets.tech/cilium_bpf_map_pressure?format=badge)<br><br>
![Darkhawk - Battery](https://biohazard-metrics.jjgadgets.tech/darkhawk_battery_percent?format=badge)

</div>

---

## Overview

This is a mono repository for all the machines in my home infrasturcture, mainly focused around Kubernetes. The main goal is automation and being as hands-off as possible in manual labour and repeated tasks, while remaining agile in making changes to the cluster.

I also explore security solutions within my homelab, due to having my own PII and personal data on my infrastructure, as well as implementing security practices in a practical home "production" environment so that I can understand how things work and how each "security positive" change may impact the end user experience, resource usage, maintenance burden and other factors.

---

## Kubernetes

### Biohazard

This is my production home Kubernetes cluster. It is powered by Talos Linux, which allows for a Kubernetes-centric and appliance-like admin experience. This is a hyperconverged setup, with most of the compute handled here, as well as highly available (HA) application storage and critical data storage in the form of Rook-Ceph, backed up in a 3-2-1 fashion using VolSync running Restic and rclone. Network routing and security is handled by Cilium, which provides powerful NetworkPolicy capabilities while having relatively low maintenance burden.

Some VMs are also run in Biohazard using KubeVirt, which allows integration of Kubernetes-centric abstractions and principles such as NetworkPolicy, DNS service discovery and GitOps, and allows Kubernetes and Rook to manage failover and lifecycle of the VMs.

### Nuclear

This is my test cluster, however it is currently not running. This cluster is used when I want to test a major change involving mass migrations and/or potential prolonged outage, such as moving from Talos VMs on Proxmox VE consuming Proxmox-managed Ceph for storage to baremetal Talos + Rook-managed Ceph.

### GitOps

Flux and Renovate provide a mostly hands-off GitOps experience, where I can push the Kubernetes resources needed to deploy a new app to this Git repo as well as update the Kustomization.yaml used by Flux to control what a given cluster should deploy. From there, Flux will automatically reconcile the changes, and Renovate will ensure updates are either automerged or proposed in Pull Requests for me to review.

## Core Components

These can be found under the `./kube/deploy/core` folder, allowing for clear separation of components that are essential for the cluster to operate to serve apps.

- **Cilium**: Provides network routing, network security, exposing apps via LoadBalancers and other networking functionality.
- **Multus**: Provides secondary network connectivity aside from Cilium, such as connecting pods and KubeVirt VMs to specific VLANs' L2 domains directly.
- **Rook-Ceph**: Provides and manages highly available networked persistent storage within the Kubernetes cluster itself.
- **VolSync**: Provides and manages automated backups and restores of persistent storage.
- **democratic-csi**: Wildcard storage CSI driver supporting multiple backends like local-hostpath.
- **Flux**: Provides GitOps automation for syncing desired state of resources.
- **external-secrets**: Syncs secrets from external sources like 1Password as Kubernetes secrets, with a templating engine.
- **k8s-gateway**: Internal DNS resolver for exposing apps via Ingress, Gateway API and LoadBalancer Services.
- **external-dns**: Syncs DNS records against upstream resolvers' records, such as Cloudflare DNS.
- **cert-manager**: Automated TLS management for generating and rotating signed and trusted TLS certificates stored as Kubernetes secrets.
- **Ingress-NGINX**: Kubernetes Ingress controller for automated configuration of NGINX to reverse proxy HTTP/S apps with automated TLS from cert-manager.
- **cloudflared**: Expose specific apps publicly via Cloudflare Zero Trust tunnel.
- **Crunchy Postgres Operator**: Automated HA Postgres cluster and backups management.
- **VictoriaMetrics**: Pull-based monitoring platform.
- **kube-prometheus-stack + prometheus-operator**: Automated configuration and service discovery for Prometheus (and thus VictoriaMetrics), with shipped defaults for Kubernetes-focused monitoring and alerting.
- **Kyverno**: Kubernetes API webhook policy engine, for validating, mutating and generating resources. Also abused as The Jank Engine.
- **Spegel**: Transparent container registry cache mirror within cluster.
- **system-upgrade-controller**: Auto-update of cluster components' versions such as Talos OS and Kubernetes versions. Combined with GitOps + Renovate for a PR-based auto-updating workflow.

## Networking

My "production" home network is currently primarily powered by Fortinet.

- Firewall: **FortiGate 40F**
- 1GbE switch: **FortiSwitch 108E**, managed, using NAC for VLAN assignment.
- 10GbE switch: **TP-Link TL-ST1008F**, unmanaged, downstream of FortiSwitch so its NAC handles VLAN assignment.
- WiFi Access Point: **FortiAP 221E**

I also tinker with and have previously used other platforms, such as OPNsense firewall, Brocade ICX6450 switch, Aruba S1500-12p switch, Cisco Catalyst 3750G, etc.
