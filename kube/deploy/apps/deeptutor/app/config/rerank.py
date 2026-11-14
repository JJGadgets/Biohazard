"""DeepTutor v1.7.2 LlamaIndex adapter for the internal llmkube reranking API.

Overrides only deeptutor.services.rag.pipelines.llamaindex.rerank in the pinned image.
Remove this overlay when upstream supports remote HTTP reranking natively.
"""

from __future__ import annotations

import json
import logging
import math
import os
from typing import Any, Callable
from urllib.request import Request, urlopen

from llama_index.core.schema import MetadataMode, NodeWithScore

logger = logging.getLogger(__name__)

# Restrict outbound reranking to the existing internal router, never arbitrary URLs.
_RERANK_URL = "http://llmkube.llmkube.svc.cluster.local/v1/rerank"
_RERANK_MODEL = "qwen3-reranker-0.6b"
_MAX_RESPONSE_BYTES = 1024 * 1024
_TIMEOUT_SECONDS = 90


def clear_reranker_cache() -> None:
    """Preserve DeepTutor's rerank module interface; no local model is cached."""


def rerank_nodes(
    query: str,
    nodes: list[Any],
    *,
    top_k: int,
    model_name: str,
    loader: Callable[[str], Any] | None = None,
) -> list[Any]:
    """Rerank using llama.cpp's Jina-compatible /v1/rerank endpoint.

    Keep the upstream non-fatal fallback to first-stage retrieval when the
    remote model is unavailable. The warning is intentionally observable.
    """
    limit = max(1, int(top_k))
    if not query or not nodes or not model_name:
        return nodes[:limit]
    if model_name != _RERANK_MODEL:
        logger.warning("Unknown DeepTutor remote reranker model %r", model_name)
        return nodes[:limit]
    if os.environ.get("DEEPTUTOR_RERANK_URL") != _RERANK_URL:
        logger.warning("Missing or unexpected DeepTutor reranker endpoint")
        return nodes[:limit]
    try:
        documents = [item.node.get_content(metadata_mode=MetadataMode.LLM) for item in nodes]
        body = json.dumps(
            {"model": _RERANK_MODEL, "query": query,
             "documents": documents, "top_n": len(documents)}
        ).encode("utf-8")
        request = Request(
            _RERANK_URL, data=body, method="POST",
            headers={"Content-Type": "application/json", "Accept": "application/json"},
        )
        with urlopen(request, timeout=_TIMEOUT_SECONDS) as response:
            if response.status != 200:
                raise ValueError(f"Reranker returned HTTP {response.status}")
            raw = response.read(_MAX_RESPONSE_BYTES + 1)
            if len(raw) > _MAX_RESPONSE_BYTES:
                raise ValueError("Reranker response exceeded size limit")
        result = json.loads(raw)
        rows = result.get("results")
        if not isinstance(rows, list) or len(rows) != len(nodes):
            raise ValueError("Reranker response has a missing/invalid results list")
        ranked: list[tuple[int, float]] = []
        seen: set[int] = set()
        for entry in rows:
            if not isinstance(entry, dict):
                raise ValueError("Invalid reranker result entry")
            index, value = entry.get("index"), entry.get("relevance_score")
            if isinstance(index, bool) or not isinstance(index, int):
                raise ValueError("Invalid reranker result index")
            if index < 0 or index >= len(nodes) or index in seen:
                raise ValueError("Duplicate or out-of-range reranker result index")
            score = float(value)
            if not math.isfinite(score) or score < 0.0 or score > 1.0:
                raise ValueError("Invalid reranker score")
            seen.add(index)
            ranked.append((index, score))
        ranked.sort(key=lambda row: row[1], reverse=True)
        return [
            NodeWithScore(node=nodes[index].node, score=score)
            for index, score in ranked[:limit]
        ]
    except Exception as exc:
        logger.warning(
            "Remote reranking failed for %d candidates; using embedding order: %s",
            len(nodes), exc,
        )
        return nodes[:limit]


__all__ = ["clear_reranker_cache", "rerank_nodes"]
