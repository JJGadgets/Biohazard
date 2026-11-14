# DeepTutor (pinned to v1.7.2)

Internal-only, Authentik forward-auth-protected DeepTutor with gVisor, Restricted
Pod Security, a single non-root replica, and a VolSync-backed `block` PVC.

## Before enabling

1. In 1Password create `deeptutor - ${CLUSTER_NAME}` containing
   `APP_DNS_DEEPTUTOR`. Create its corresponding internal DNS record.
2. Ensure the Authentik Envoy forward-auth outpost permits the chosen
   internal hostname. The gateway route is `deeptutor-app`.
3. Confirm the `llmkube` router currently serves model IDs
   `qwen3.8-27b-pro`, `qwen3-embedding-0.6b`, and
   `qwen3-reranker-0.6b`, through
   `http://llmkube.llmkube.svc.cluster.local/v1`.
4. Confirm the Pod is permitted by the existing ingress/egress cluster policies:
   `ingress.home.arpa/envoy-internal=allow` and
   `ai.internal/llmkube=allow`. No public Gateway or world egress is granted.

## Bootstrap and persistence

A non-root init container seeds `/app/data/user/settings/model_catalog.json`,
`llamaindex.json`, and `system.json` **only if they do not exist**.
The full `/app/data` tree is backed up (including credentials, databases,
sessions, workspaces, knowledge bases, and system state). Subsequent UI edits
survive restarts, but editing the seeded ConfigMap does **not** overwrite
existing PVC settings; migrate them explicitly if changing a model ID.

The LLM and task model use the OpenAI **Chat Completions** format, since
llmkube does not expose `/v1/responses`. Embeddings use the full
`/v1/embeddings` URL and 1024-dimensional Qwen3 vectors; changing the
embedding model or dimensions requires reindexing knowledge bases.

## Remote reranking compatibility adapter

Upstream DeepTutor v1.7.2 supports **local** SentenceTransformers
CrossEncoder reranking only; it has no external HTTP rerank provider. To avoid
silently loading a local CPU model or discarding reranking, this deployment
mounts a version-specific `rerank.py` ConfigMap over its LlamaIndex
reranker module, using the existing llama.cpp `/v1/rerank` API.

The adapter:
- Targets exactly the internal llmkube rerank URL and pinned model ID.
- Bounds HTTP time (90 s) and response size (1 MiB).
- Validates each returned index and score before reordering source nodes.
- Logs a warning and preserves upstream first-stage retrieval ordering if
  the router/model is unavailable or replies with malformed data.
- Only applies to **LlamaIndex** knowledge bases; other RAG engines do not
  automatically share this reranker.

This overlay depends on DeepTutor's v1.7.2 internal `rerank_nodes` interface.
Review/retest it before updating the DeepTutor image. Remove it once an upstream
remote reranker API is available. The Reloader pod annotation restarts on
ConfigMap changes because the file is mounted as a subPath.

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
- Check the DeepTutor provider settings show the three configured model IDs.
  Test chat, embedding, and an actual LlamaIndex KB retrieval. Confirm the
  router receives a `POST /v1/rerank` call and the sorted result order changes.
- Ingest a small KB; verify vectors are 1024-wide, then exercise retrieval.
  If the rerank API is unavailable, check the warning logs: DeepTutor continues
  with embedding-ranked hits, not CPU reranking.
- Confirm an unauthenticated request to the internal Gateway is denied or
  redirected by Authentik, and no path through the Service is exposed publicly.
- Validate the effective `HelmRelease`, ConfigMap, Secret and PVC with
  `flux-local` or `kustomize build`; no live cluster verification is
  performed by this PR.
