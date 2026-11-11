# AMD GPU Operator / DRA on the R9700

Install AMD GPU Operator v1.5.1 and DRA v1.0.1 with a version-pinned
Helm chart and digest-pinned images. AMD's controller, privileged DRA
plugin and metrics-exporter are restricted to the `kube-amd-gpu`
namespace; Radiance is still non-root and least privileged.

The existing NFD installs the AMD GPU NodeFeatureRule matching PCI
`1002:7551`. The DeviceConfig only manages `sinon`, reuses Talos'
AMDGPU kernel driver and disables KMM/driver installation, traditional
AMD device plugin, node labeller, hardware partitioning, test runner
and auto-remediation.

LLMKube uses the fixed namespaced
`llmkube/qwen3.8-27b-radiance` ResourceClaim to allocate one GPU.
This claim may be used by additional trusted pods **in llmkube**.
It cannot be referenced from another namespace. AMD DRA 1.0.1 does
not allow multiple independent allocations of an unpartitioned GPU:
**direct cross-namespace GPU sharing is not supported**. Using the
Radiance service via the router from other namespaces is supported
by the existing Cilium policies but is not raw GPU sharing.
The R9700 also offers no isolated VRAM or compute partitions.

Before production: verify amdgpu 6.19+ / ROCm 7.13+, CDI, R9700
`ResourceSlice`, shared-claim access from two non-root llmkube Pods,
pinned image digests against the registry, Talos driver ownership
and appropriate privileged-namespace isolation. AMD's operator
v1.5.1 R9700 support list validates traditional device-plugin
scheduling and metrics, not DRA on R9700 hardware.

Sources:
- https://github.com/ROCm/gpu-operator/releases/tag/v1.5.1
- https://github.com/ROCm/k8s-gpu-dra-driver/releases/tag/v1.0.1
- https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/dra-api/
