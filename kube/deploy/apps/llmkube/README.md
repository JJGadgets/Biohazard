# LLMKube

Model manifests are grouped by responsibility: `models/common.yaml` holds shared storage, pool/router, and the HTTP port-80 alias; `models/qwen3.6-35b-a3b.yaml`, `models/embed.yaml`, and `models/rerank.yaml` keep model-specific resources together.

LLMKube 0.10.7 is installed through its upstream OCI Helm chart and Flux
HelmRelease. The Qwen weights/projector, embedding and reranker GGUFs, and
chat template are fetched by LLMKube-managed prefetch Jobs at pinned Hugging
Face revisions before the serving pod is created. There is no app-owned download Job. The operator's
prefetch pods are labeled `app.kubernetes.io/component=model-prefetch`; the
app's Cilium policy allows that workload class only Hugging Face TCP/443 and
L7-filtered DNS queries for `huggingface.co` and `*.huggingface.co`. This
restriction is scoped to the prefetch pods; no shared cluster network policy is
modified by this app.

The app-owned PVCs in `models/common.yaml` are the intended workload storage:
`llmkube-models` is explicitly selected by the Qwen `InferenceService`,
`llmkube-templates` by the chat-template `Model`, and `llmkube-runtime-data`
stores llama.cpp runtime state. All use the `local` storage class; model prefetch and
serving are pinned to `kubernetes.io/hostname=sinon`. The serving pod mounts
the staged model and template artifacts read-only. The chart's
`modelCache.mode/size/storageClass` settings are fallback provisioning for
services without an explicit `spec.modelCache.claimName`.

## Metrics

Prometheus discovery is configured for all three LLMKube metric sources:

- The chart-managed `ServiceMonitor` scrapes controller-manager/operator
  metrics from the internal metrics Service on port 8443.
- The namespace-scoped `PodMonitor/llmkube-inference` scrapes each LLMKube
  inference runtime's `/metrics` endpoint on its `http` port. For llama.cpp,
  this includes the Prometheus metrics such as prompt/generation tokens,
  throughput, in-flight requests, and deferred requests.
- The namespace-scoped `PodMonitor/llmkube-router` scrapes router-proxy
  metrics on its dedicated `metrics` port (9090), including model-pool
  residency, swap, and request-hold metrics.

The monitors are labeled `prometheus: kps` for the cluster's KPS instance and
scrape every 60 seconds to match the Prometheus configuration. The inference
and router PodMonitors deliberately match only pods in namespace `llmkube`,
rather than using the upstream chart's any-namespace selector. The controller
metrics Service uses HTTP on its internal ClusterIP; Cilium permits port 8443
only from the Prometheus pods in namespace `monitoring`. Runtime scrapes are
limited to `GET /metrics`; the router is the only other allowed runtime caller.
The router proxy itself accepts model API ingress only from pods explicitly
labeled `ai.internal/llmkube=allow`. DNS egress for controller and router uses
the existing cluster default instead of duplicate app-local allow rules.

## Embedding and reranking

The Qwen3 Embedding and Qwen3 Reranker services share the existing
`llmkube-router` ModelPool with Qwen 3.6. Request model `qwen3-embedding-0.6b`
through `/v1/embeddings` and model `qwen3-reranker-0.6b` through `/v1/rerank`
using the shared base URL:

`http://llmkube-router-proxy.llmkube.svc.cluster.local/v1`

The app-owned `Service/llmkube-router-proxy` maps port 80 to the router pod's
port 8080. LLMKube's current ModelRouter API does not expose an independent
`targetPort`: the controller uses `spec.endpoint.port` for both the generated
Service port and targetPort, while the generated proxy Deployment binds to 8080.
Setting `endpoint.port: 80` would therefore point the Service at an unused port
inside the pod; the alias is retained until upstream adds separate target-port
support.

Both inference services are pinned to `sinon`, tolerate its
`llm.internal:NoSchedule` taint, and request both NVIDIA device-plugin GPUs so
CUDA device 1 remains visible in the pod. `CUDA_DEVICE_ORDER=PCI_BUS_ID` and
`LLAMA_ARG_DEVICE=CUDA1` select the GTX 1060 for inference. The ModelPool
serializes the services against the same two-GPU allocation.

The unified Cilium policy selects only pods carrying `netpol: llmkube-models` and `inference.llmkube.dev/runtime: llamacpp`; model API ingress is L4-only, while L7 HTTP filtering remains limited to `GET /metrics`.

The services use llama.cpp's explicit `--load-mode mlock` setting, which keeps
model pages resident without using mmap. This replaces the deprecated `--mlock`
flag and avoids setting the older mmap environment variables. The namespace's Pod Security `baseline` enforcement remains intact;
no `IPC_LOCK` capability is added, so whether the kernel can lock all model
pages depends on the container runtime's memlock limit.

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
- The stock NVIDIA GPU Operator setup uses the legacy `nvidia.com/gpu`
  device-plugin resource, which allocates a number of devices but does not
  select an individual GPU UUID from an `InferenceService`. The Qwen service
  requests both NVIDIA GPUs present on `sinon`; `CUDA_DEVICE_ORDER=PCI_BUS_ID`
  and the existing `CUDA0`/`CUDA1` settings establish their logical order
  within the allocated devices. Pinning UUIDs on a node with additional GPUs
  would require enabling NVIDIA DRA with ResourceClaims or configuring
  per-device extended resources in the cluster's GPU device plugin.
- The generated ModelRouter proxy hard-codes UID 65532 and has no
  `runtimeClassName` setting in `ModelRouter.spec.proxy`. LLMKube's generated
  prefetch Job also has no CRD field to override its RuntimeClass or downloader
  UID, so its built-in downloader uses the upstream init-image defaults rather
  than `APP_UID_LLMKUBE`/gVisor.
- The prefetch Job includes an upstream `model-cache-prep` init container that
  runs as UID 0 with `CHOWN` and `FOWNER`. This is incompatible with Pod
  Security Admission's `restricted` enforcement. To keep operator-managed
  prefetch functional, this namespace enforces `baseline` and retains
  `restricted` audit/warn labels. The app-owned controller retains explicit
  hardening, and Cilium policies isolate model downloads from serving workloads.
  The generated prefetch init is not gVisor isolated until upstream exposes a
  runtime-class override.
- The app-owned controller uses the configured UID and gVisor. Both operator-
  generated model-prefetch jobs currently use the upstream downloader image and
  security settings because LLMKube does not expose per-prefetch UID or runtime
  overrides. The model-serving pod is intentionally not assigned gVisor because
  it requires NVIDIA device passthrough.

The router remains an internal ClusterIP service; no external route or
authentication policy is created here. Client Pods must be explicitly opted in
with the label `ai.internal/llmkube=allow`; without that label Cilium denies
access to the router API.
