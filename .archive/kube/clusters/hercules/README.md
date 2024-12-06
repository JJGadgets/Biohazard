# Hercules cluster
Single-node k3s cluster on OVH, used for L4 ingress to home prod cluster Biohazard, STUN, home VPN "control-plane-based" solutions like Headscale/Netmaker, and other "chicken-and-egg" apps.

## Hardware
+ OVH Starter VPS
+ 1 vCPU
+ 2GB RAM
+ 20GB VM disk
+ 1TB 100Mbps network, throttles to 10Mbps after

## Software
+ OS: Kairos Linux
+ Kubernetes: k3s
