# AMD GPU Operator / DRA on the R9700

Install AMD GPU Operator v1.5.1 and DRA v1.0.1 with a version-pinned
Helm chart and digest-pinned images. AMD's controller, privileged DRA
plugin and metrics-exporter are restricted to the `amd-gpu-operator`
namespace; Radiance is still non-root and least privileged.

The existing NFD installs the AMD GPU NodeFeatureRule matching PCI
`1002:7551`. The DeviceConfig only manages `sinon`, reuses Talos'
AMDGPU kernel driver and disables KMM/driver installation, traditional
AMD device plugin, node labeller, hardware partitioning, test runner
and auto-remediation.

The named ResourceClaim selects only an unpartitioned AMD GPU with PCI
ID 0x7551, to avoid accidentally allocating a different Radeon/Instinct
GPU as the cluster evolves. Confirm the DRA ResourceSlice advertises
that exact deviceID before allowing reconciliation.

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

## R9700 startup tuning

A DaemonSet runs a privileged init container on `sinon` at pod startup. It
checks PCI address `0000:03:00.0` is AMD device `1002:7551`, then sets a
-75 mV voltage offset, 70°C automatic fan target, and 250 W power cap. The
init container logs the resulting driver readback; its unprivileged companion
keeps the pod alive without polling. A GPU or driver reset after startup may
reset settings; restart the pod to apply them again.

The supplied sysfs inventory did not expose `pp_od_clk_voltage` or
`gpu_od/fan_ctrl/fan_target_temperature`. The init container will fail until
the driver exposes both controls (including any required overdrive kernel
configuration). Check init-container logs and validate the reported settings
and GPU stability on the hardware before relying on them. A failed write can
leave earlier settings applied; investigate the logs before retrying.

The voltage and fan controls follow the [kernel AMDGPU documentation](https://docs.kernel.org/gpu/amdgpu/thermal.html).

The driver must support voltage offsets and the automatic fan-target interface
for this card, and its firmware must expose ranges including the requested
values. AMDGPU OverDrive uses bit `0x4000` in `amdgpu.ppfeaturemask`. If the
interfaces are absent, inspect the running mask at
`/sys/module/amdgpu/parameters/ppfeaturemask`, preserve its other bits, and
set bit `0x4000` in the Talos kernel command line (for example, the upstream
Linux default `0xfff7bfff` becomes `amdgpu.ppfeaturemask=0xfff7ffff`). The
actual running mask and hardware support must be checked on `sinon`; this
repository does not configure that node's boot parameters. Reboot after any
boot-parameter change and confirm the interfaces and their advertised ranges
before reconciliation. See the kernel's [feature mask definitions](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/include/amd_shared.h).
