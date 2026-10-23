# LLMKube

LLMKube 0.10.7 is installed through its upstream OCI Helm chart and Flux
HelmRelease. Both the Qwen weights/projector and chat template are fetched by
LLMKube-managed prefetch Jobs at pinned Hugging Face revisions, before the
serving pod is created. There is no app-owned download Job. The operator's
prefetch pods are labeled `app.kubernetes.io/component=model-prefetch`; the
app's Cilium policy allows that workload class only Hugging Face TCP/443 and
DNS queries for `huggingface.co` and `*.huggingface.co`. The cluster-wide
generic DNS egress policy excludes this dedicated component so its generic DNS
allowance cannot override the app-specific DNS rule.

The model cache and chat-template PVC use `local-hostpath` and are first
consumed by workloads pinned to `kubernetes.io/hostname=sinon`. The serving
pod mounts both staged artifacts read-only.

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
- The app-owned controller uses the configured UID and gVisor. Both operator-
  generated model-prefetch jobs currently use the upstream downloader image and
  security settings because LLMKube does not expose per-prefetch UID or runtime
  overrides. The model-serving pod is intentionally not assigned gVisor because
  it requires NVIDIA device passthrough.

The router remains an internal ClusterIP service; no external route or
authentication policy is created here.
