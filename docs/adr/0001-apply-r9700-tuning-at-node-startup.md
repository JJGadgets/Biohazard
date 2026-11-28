# ADR-0001: Apply R9700 tuning at node startup

## Status

Proposed

## Date

2026-11-13

## Context

The AMD GPU Operator component is reconciled by Flux into the privileged
`amd-gpu-operator` namespace and manages the R9700 on `sinon` using the
Talos-managed AMDGPU driver. The desired operating settings are a -75 mV
voltage offset, a 70 °C fan target, and a 250 W power cap. These are
node-local driver settings and need to be applied again after node startup.
The user requests a single application per startup, without polling or dynamic
control.

The supplied device inspection identifies PCI device `0000:03:00.0` as AMD
`1002:7551`. Its sysfs listing includes a power cap interface, but does not
show the voltage offset or fan target interfaces. Their availability and the
required driver configuration on the running node remain unverified.

## Decision drivers

- Reconcile configuration through the existing Flux-managed component.
- Apply the requested settings to the intended GPU on `sinon`, without
  accidentally changing another device.
- Make failures visible and avoid a long-lived privileged controller.
- Limit host access and preserve the existing default-deny network posture.

## Decision

Use a `sinon`-scoped DaemonSet in the existing AMD GPU Operator component to
apply the settings once when its pod starts. A privileged init container will
verify the target PCI identity and apply the settings through AMDGPU sysfs;
a non-privileged container will keep the pod running afterward. Missing or
unsupported interfaces must result in a visible failure rather than a claim
of success.

## Rationale

A DaemonSet follows node startup and fits the repository's GitOps model. An
init container bounds privileged execution to configuration time while the
persistent pod prevents successful runs from being continuously restarted.
Checking the PCI identity before writes reduces the risk of tuning a different
GPU. The chosen architecture does not require a network service, Kubernetes
API credentials, or a polling loop.

## Alternatives considered

- **Status quo:** Leave settings at driver defaults. This has no additional
  privileged workload but does not satisfy the requested settings.
- **Configure the host during boot:** Apply settings from Talos host
  configuration. This could avoid a persistent pod, but requires suitable Talos
  host support and a separate host configuration path; the existing operator
  component already owns GPU-related Kubernetes configuration.
- **Run a continuous privileged tuning controller:** Monitor and reapply
  settings after driver resets. This offers stronger ongoing convergence, but
  expands privileged runtime and complexity beyond the requested one-shot
  behavior.

## Consequences

- The tuning process has privileged host access and can affect the host
  kernel. Scope its scheduling and mounts to the target node and device, disable
  unnecessary credentials and networking, and use a pinned image.
- The kernel and hardware must expose and accept each requested control. In
  particular, voltage and fan controls may require AMDGPU overdrive to be
  enabled; this has not been confirmed on `sinon`. Operators must verify the
  controls and read back the actual settings on the node.
- A driver reset after successful initialization can discard settings. This
  design does not detect or repair that condition; restarting the pod reapplies
  them. Removing the DaemonSet does not itself restore driver defaults.
- Settings can affect GPU stability, thermals, and performance; successful
  writes do not establish stability under load. Validate the hardware after
  rollout.

## References

- [AMDGPU thermal and power controls](https://docs.kernel.org/gpu/amdgpu/thermal.html)
- [AMD GPU Operator component](../../kube/deploy/core/hardware/amd-gpu-operator/README.md)
