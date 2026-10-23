# LLMKube

LLMKube 0.10.7 is installed through its upstream OCI Helm chart and Flux
HelmRelease. The Qwen weights and multimodal projector are fetched by
LLMKube's own prefetch Job at a pinned Hugging Face revision, before any serving
pod is created. The operator's prefetch job selector is
`app.kubernetes.io/component=model-prefetch`; the app's Cilium policy only
permits this workload class to reach Hugging Face over TCP/443 and applies a DNS L7 allowlist for `huggingface.co` and `*.huggingface.co`. The cluster-wide generic DNS egress policy excludes this dedicated component so its unrestricted DNS allowance cannot override the app-specific DNS rule.

The separate chat-template Job uses the same narrowly scoped egress policy.
Both the model cache and chat-template PVC use `local-hostpath` and are first
consumed by workloads pinned to `kubernetes.io/hostname=sinon`. The serving
pod mounts the prefetched model cache and chat template read-only.

## Adding another swappable model

Add a `Model` and `InferenceService`, include the service in the
`ModelPool.spec.members`, then add its backend and model-matching rule to the
`ModelRouter`. Keep `proxy.replicas: 1`: upstream serializes GPU-slot swaps
inside one router process. Cross-model requests to `/v1/chat/completions` are
held while the incumbent drains and the requested model loads, up to
`swapBudget`; an exhausted budget returns HTTP 503 with `Retry-After`.

## Upstream LLMKube limitations in v0.10.7

- The router-proxy registers `/v1/chat/completions`, `/v1/completions`,
  `/v1/embeddings`, and `/v1/rerank`, but does not register
  `/v1/responses`. Request-held swaps therefore work for Chat Completions but
  require an upstream change for the Responses API.
- The generated ModelRouter proxy hard-codes UID 65532 and has no
  `runtimeClassName` setting in `ModelRouter.spec.proxy`. LLMKube's generated
  prefetch Job also has no CRD field to override its RuntimeClass or downloader
  UID, so its built-in downloader uses the upstream init-image defaults rather
  than `APP_UID_LLMKUBE`/gVisor.
- The prefetch Job includes an upstream `model-cache-prep` init container that
  runs as UID 0 with `CHOWN` and `FOWNER`. This is incompatible with Pod
  Security Admission's `restricted` enforcement. To keep operator-managed
  prefetch functional, this namespace enforces `baseline` and retains
  `restricted` audit/warn labels. App-owned controller and chat-template
  containers retain explicit hardening, and Cilium policies isolate model
  downloads from serving workloads. The generated prefetch init is not gVisor
  isolated until upstream exposes a runtime-class override.
- The app-owned controller and chat-template Job use the configured UID; the
  controller and chat-template Job are configured for gVisor. The model-serving
  pod is intentionally not assigned gVisor because it requires NVIDIA device
  passthrough.

The router remains an internal ClusterIP service; no external route or
authentication policy is created here.
