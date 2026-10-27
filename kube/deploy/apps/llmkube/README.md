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

The Qwen3 Embedding and Qwen3 Reranker use independent ModelPools from Qwen
3.6. `llmkube-llm`, `llmkube-embedding`, and `llmkube-rerank` each manage
only their own role. A request for one role cannot scale another role to zero;
future alternatives swap only within their role's pool. Use model IDs
`qwen3-embedding-0.6b` with `/v1/embeddings` and
`qwen3-reranker-0.6b` with `/v1/rerank` at:

`http://llmkube.llmkube.svc.cluster.local/v1`

The app-owned `Service/llmkube` maps port 80 to the router pod's port 8080.
LLMKube 0.10.7's generated ModelRouter Service uses the same port for service
and targetPort, so `endpoint.port: 80` would target an unused pod port; the
separate alias service remains necessary.

## GPU allocation: Tesla T4 exclusive, GTX 1060 time-sliced

The NVIDIA GPU Operator's legacy device-plugin time-slicing config applies to
every GPU on a node, so it cannot time-slice the GTX 1060 alone. This setup
disables the legacy device plugin and uses NVIDIA's DRA driver, pinned to chart
v0.5.1 and restricted to `sinon`.

Two static `ResourceClaim`s in the `llmkube` namespace select full devices by
their DRA-published product names:

- `llmkube-tesla-t4-exclusive` selects one Tesla T4 and omits sharing config.
  The LLM pool keeps Qwen at one replica, and a future LLM swap uses this same
  exclusive claim.
- `llmkube-gtx1060-time-sliced` selects one GTX 1060 and adds
  `GpuConfig.sharing.strategy: TimeSlicing`. Qwen, embedding, and reranking
  reference the same claim, so they can share one physical GPU without giving
  the smaller model services access to the T4.

The DRA driver's `TimeSlicingSettings` feature gate is Alpha. Time-slicing
does not provide GPU-memory isolation or throughput guarantees. The claim uses
the default time-slice interval; no device-plugin replica multiplier is applied
to the T4. The driver's published time-slicing guide documents claim-scoped
configuration and CEL device selectors, including selecting a particular GPU.

Qwen requests both DRA claims and stays at one replica; its
`CUDA_DEVICE_ORDER=PCI_BUS_ID` preserves the existing `CUDA0`/`CUDA1`
device selection. Embedding and reranking request only the GTX 1060 claim and
see the single allocated device as `CUDA0`. The latest model tuning from main
is retained: embedding uses 16K context, 6 parallel slots, batch 384/ubatch
192; reranking uses 8K context, 2 parallel slots, batch 384/ubatch 192. Both
retain a `1Gi` memory request.

The unified Cilium policy keeps inference API ingress L4-only, while L7 HTTP
filtering remains limited to `GET /metrics`. The LLMKube models Kustomization
depends on `nvidia-app` so the DRA driver and device class reconcile first.

## Adding another swappable model

Add a `Model` and `InferenceService`, include the service only in its
role-specific `ModelPool.spec.members`, then add its backend and matching
rule to `ModelRouter`. A new LLM must reference both the T4-exclusive and
GTX1060-time-sliced claims; an alternate embedding or reranker references only
the GTX claim. Keep `proxy.replicas: 1`: LLMKube serializes swaps within each
pool, holding requests while a target model loads up to `swapBudget`.

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
