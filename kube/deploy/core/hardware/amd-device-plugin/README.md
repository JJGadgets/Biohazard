# AMD R9700 shared device plugin

This is the upstream `squat/generic-device-plugin` restricted to the AMD
R9700 on `sinon`, not a privileged AMD GPU operator. It registers two
independent Kubernetes extended-resource allocations under
`devic.es/amd-r9700-shared`. Each allocation passes the **same physical**
`/dev/kfd` and R9700 DRM render character device to a pod. This permits
sharing between trusted pods; it does **not** enforce VRAM quotas, GPU
compute isolation, or fair scheduling.

## Required machine-side device identity

**The DaemonSet is fail closed until `/dev/dri/r9700-render` exists.**
Provision a persistent udev alias on `sinon` pointing to the DRM render
node whose PCI vendor is 0x1002 and whose product is **the R9700**.
Verify the PCI BDF and associated `/sys/class/drm/renderD*/device/vendor`,
device ID and `readlink -f` before enabling the daemonset. Do not assume
`renderD128` is the AMD card: this host also schedules NVIDIA models.

Kubelet's device-plugin Unix sockets live in a root-owned hostPath.
Consequently this DaemonSet must register as UID 0 (without privileged,
capabilities, privilege escalation, host network or service-account token).
The workload itself runs as a non-root UID. A fully rootless *plugin daemon*
would require a separately provisioned kubelet socket directory ACL and
testing on Talos; no claim of such support is made here.

For non-root GPU access, the host must already set containerd's
`device_ownership_from_security_context=true`, as the Biohazard
Talos config does, and the host driver must expose `/dev/kfd` and the
selected render device. Admission errors, missing host aliases, missing
ROCm-compatible kernel support and seccomp-denied syscalls should fail
closed rather than broaden container privileges.

The Radiance service is intentionally pinned to the existing `sinon` local
model/template PVCs. Verify the R9700 and both claims are actually on that
node. If not, migrate all three together rather than swapping a node label
on only one manifest.

The plugin's CDI/device-plugin allocation maps the verified R9700 character
device into the pod as `/dev/dri/renderD128` for normal ROCm enumeration.
That in-container name must not be mistaken for a host GPU index.
