# Open Notebook (cluster biohazard)

- **App:** [Open Notebook v1.15.1](https://github.com/lfnovo/open-notebook/releases/tag/v1.15.1), pinned by its published OCI digest.
- **DB:** official SurrealDB v2 (immutable OCI digest), embedded as a sidecar in the **same pod**, bound to loopback only. The upstream single-container image is deprecated; this arrangement instead follows the separate-DB deployment architecture without advertising a DB Service.
- **Storage:** `open-notebook-data` (20Gi Ceph RBD `block`, RWO, VolSync enabled). The app and database mount distinct directories under one claim. `Recreate` strategy ensures one RocksDB writer. **Important:** live file-level VolSync/Restic backups of RocksDB are not application-consistent. Verify database recoverability from snapshots and implement a quiesced/native database export strategy before relying on them for disaster recovery. Keep database and encryption-key backups together in a protected recovery procedure.
- **Network:** internal HTTPS UI only via Envoy, no public ingress; no SurrealDB Service; API Service `open-notebook-api.open-notebook.svc.cluster.local:5055` admits only the ToolHive MCP adapter under the app Cilium policy. Pod opts into `ai.internal/llmkube=allow`. No internet egress or public model service is required for text and local PDF sources.
- **Sandbox:** gVisor, Pod Security Restricted, non-root UID 65532, root filesystem read-only, all Linux capabilities dropped, no service-account token. Check upstream image compatibility with rootless + gVisor and the persistent subPath mounts in a staging rollout.

## Prerequisites in 1Password

Create **`Open Notebook - ${CLUSTER_NAME}`** (for this cluster: `Open Notebook - biohazard`) with:
- `OPEN_NOTEBOOK_PASSWORD`: unique randomly generated high-entropy login/API bearer password (MCP adapter uses the same value).
- `OPEN_NOTEBOOK_ENCRYPTION_KEY`: distinct, stable, randomly generated high-entropy encryption key. Losing it means encrypted provider credentials cannot be recovered.
- `SURREAL_PASSWORD`: distinct high-entropy database root password.
- `APP_DNS_OPEN_NOTEBOOK`: internal HTTPS domain configured for Envoy Gateway.

The app and MCP namespace each get an independently scoped ExternalSecret from 1Password; no credentials are committed. The `-vars` ExternalSecret also imports `CONFIG_TZ` from cluster variables.

## Configure models after first boot

Open Notebook **v1.15.1 uses database-backed provider and model registration**, not declarative model-ID environment variables. The deployment sets the legacy fallback provider URL to `http://llmkube-router-proxy.llmkube.svc.cluster.local/v1` for first boot, but an explicit provider and model selection in **Manage → Models** is required before chat and search operate.

1. Add **OpenAI Compatible** provider, base URL `http://llmkube-router-proxy.llmkube.svc.cluster.local/v1`; use no API key if supported, or a harmless non-secret placeholder if the form requires one.
2. Register **language model `qwen3.8-27b`** as the chat / transformation / tools / large-context model, selecting this ID manually if the router's /models catalog does not advertise it.
3. Register **embedding model `qwen3-embedding-0.6b`** as the default embedding model.
4. Test both providers from Open Notebook and ingest a small source to verify embeddings / search.
5. The router also serves **`qwen3-reranker-0.6b`** on `/v1/rerank`. **Open Notebook v1.15.1 does not perform reranking**, so no reranker configuration is activated. Do not mistake the existence of `ESPERANTO_RERANKER_TIMEOUT` for application-level reranking support. If upstream adds a reranker, connect it to this same router.

The router currently swaps model backends; avoid many concurrent worker operations (`OPEN_NOTEBOOK_WORKER_MAX_TASKS=1`). API calls have a 540-second internal LLM timeout; browser requests have a separate 600-second timeout.

## MCP via ToolHive

`kube/deploy/apps/toolhive/mcp/open-notebook.yaml` registers `MCPServer/open-notebook` with the existing `MCPGroup/mcp`, consumed by `VirtualMCPServer/mcp`. The adapter listens on streamable HTTP :8000, uses the private API Service above and receives `OPEN_NOTEBOOK_PASSWORD` only from a namespace-local ExternalSecret.

Because the official [Epochal-dev/open-notebook-mcp](https://github.com/Epochal-dev/open-notebook-mcp) publishes Python code/PyPI packages but no verified OCI image, the ToolHive MCPServer uses the **same digest-pinned Open Notebook runtime image** with the upstream server Python source at commit `a2cddbf65cba8c4c8de7be16566781b7612a9545` mounted from a ConfigMap. Its imports (`httpx`, `mcp.server.fastmcp`) are already present in the Open Notebook image's pinned runtime dependency graph (`mcp==1.28.1` in the published `uv.lock`); this avoids installing unpinned dependencies or allowing PyPI egress at runtime. The third-party source is included under its upstream MIT license in the ConfigMap for provenance. The adapter is still a separate ToolHive-managed MCP workload with a read-only root filesystem, no elevated privileges, and gVisor. Audit adapter functionality and fastmcp compatibility before enabling in production; upstream compatibility is not guaranteed across package or image updates.

MCP tools include **write/delete** functionality for notebooks and content. Restrict access to trusted agents via existing vMCP policies and review permissions; `VirtualMCPServer/mcp` currently has anonymous incoming auth, mitigated only by existing network isolation / internal Gateway IP allowlist. This deployment does **not** widen those controls.

## Staging validation

- Verify both `open-notebook` containers start and `GET /health` on port 5055 succeeds, with a non-default SurrealDB password.
- Confirm the internal frontend route serves the UI and proxies `/api/*` without exposing port 5055 to arbitrary pods.
- Confirm models work with the router, while outbound traffic to public model providers stays denied.
- Confirm ToolHive `MCPServer/open-notebook` becomes ready and vMCP discovers `open-notebook_search_capabilities`; run a read-only notebook listing before testing writes.
- Confirm SurrealDB survives pod recreation and restore a test PVC snapshot **with native DB verification**. Do not assume live Restic copies are consistent.
- Verify the effective Helm template keeps Restricted securityContexts and no undesired host privileges or internet egress.
