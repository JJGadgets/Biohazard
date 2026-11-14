# DeepTutor (pinned to v1.7.2)

Internal-only, Authentik forward-auth-protected DeepTutor with gVisor, Restricted
Pod Security, a single non-root replica, and a VolSync-backed `block` PVC.

The app manifests follow `kube/templates/test/` (app-template chart `5.0.1`,
app-local `app/chart.yaml`, Flux PVC metadata and namespace-scoped network
policy). No `app/es.yaml` is deployed because DeepTutor does not require
application-specific credentials; the only required variable is loaded
through `vars.yaml`. gVisor is retained for isolation rather than switching
to the template's alternative user-namespace runtime.

## Before enabling

1. In 1Password create `deeptutor - ${CLUSTER_NAME}` containing
   `APP_DNS_DEEPTUTOR`. Create its corresponding internal DNS record.
2. Ensure the Authentik Envoy forward-auth outpost permits the chosen
   internal hostname. The gateway route is `deeptutor-app`.
3. Confirm the `llmkube` router currently serves model IDs
   `qwen3.8-27b-pro` and `qwen3-embedding-0.6b` through
   `http://llmkube.llmkube.svc.cluster.local/v1`.
4. Confirm the Pod is permitted by the existing ingress/egress cluster policies:
   `ingress.home.arpa/envoy-internal=allow` and
   `ai.internal/llmkube=allow`. No public Gateway or world egress is granted.

## Bootstrap and persistence

A non-root init container seeds `/app/data/user/settings/model_catalog.json`,
and `system.json` **only if they do not exist**.
The full `/app/data` tree is backed up (including credentials, databases,
sessions, workspaces, knowledge bases, and system state). Subsequent UI edits
survive restarts, but editing the seeded ConfigMap does **not** overwrite
existing PVC settings; migrate them explicitly if changing a model ID.

The LLM and task model use the OpenAI **Chat Completions** format, since
llmkube does not expose `/v1/responses`. Embeddings use the full
`/v1/embeddings` URL and 1024-dimensional Qwen3 vectors; changing the
embedding model or dimensions requires reindexing knowledge bases.

## Retrieval without reranking

DeepTutor v1.7.2 defaults to an empty `reranker_model`, which disables
the optional reranking stage. LlamaIndex continues to retrieve passages
using vector or hybrid BM25/vector retrieval, with no extra model downloads
and no custom Python code mounted into the application. Other core tutor
features remain available.

DeepTutor's native cross-encoder reranking is deliberately not configured:
it supports local SentenceTransformers models rather than the llmkube
HTTP reranking endpoint. This removes the maintenance burden and upgrade
risk of patching internal DeepTutor modules. If upgrading an existing
deployment, check the persisted
`/app/data/user/settings/llamaindex.json` and clear
`reranker_model` if it was previously set; bootstrap settings never
overwrite existing PVC files.

## Security

The application has no external/public HTTPRoute or Internet egress. Incoming
traffic is gated through Authentik forward auth at the Envoy internal Gateway.
DeepTutor's built-in auth is disabled; direct access to its Service would bypass
Gateway auth, so the cluster's default-deny and Envoy-only ingress label must
remain enforced. The container does not receive a Kubernetes API token or
Linux capabilities. Its code-execution subprocess sandbox is disabled
(`sandbox_allow_subprocess=false`); office/exec-dependent features will
therefore be unavailable without a separately isolated runner. The app does
not download optional dependencies or external models at runtime.

## Validation after deployment

- Verify both backend `/health/ready` and frontend `/` respond inside
  the Pod; only the frontend is published through the internal Gateway.
- Check the DeepTutor provider settings show the two configured model IDs.
  Test chat, embeddings, and a LlamaIndex KB retrieval without reranking.
- Ingest a small KB; verify vectors are 1024-wide, then exercise vector
  and/or hybrid BM25/vector retrieval.
- Confirm an unauthenticated request to the internal Gateway is denied or
  redirected by Authentik, and no path through the Service is exposed publicly.
- Validate the effective `HelmRelease`, ConfigMap, Secret and PVC with
  `flux-local` or `kustomize build`; no live cluster verification is
  performed by this PR.
