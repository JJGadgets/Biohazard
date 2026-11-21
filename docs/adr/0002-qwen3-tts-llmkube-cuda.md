# ADR-0002: Serve Qwen3-TTS through LLMKube on the Tesla T4

## Status

Proposed

## Date

2026-11-22

## Context

The cluster needs locally hosted text-to-speech using Qwen3-TTS 12Hz 1.7B Base. LLMKube already routes inference services and manages model pools; its existing `sinon-embed` pool selects `sinon`, while a separate Tesla T4 pool is currently commented out. The model must share a node with other GPU workloads. Capacity, latency, audio quality, and end-to-end compatibility on this cluster have not been measured.

Upstream llama.cpp documents Qwen3-TTS support and speech endpoints. The `ggml-org` GGUF conversion is published separately from Qwen's original model. The Base model supports reference-voice conditioning; reference audio and generated speech may contain sensitive personal data and voice cloning can be misused.

## Decision

Serve the `ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF` Q8_0 model through LLMKube using llama.cpp's CUDA server on the NVIDIA Tesla T4 in `sinon`. Pin the model repository revision to `ca27d74bc954b73dadab5b71ca265d87fc861a7c`, and pin the server image to `ghcr.io/ggml-org/llama.cpp:server-cuda12-b12602@sha256:26f89ebd3bf17a5ecf6caee62bdabfa55abea3058150879f6f07b1fc786baa2d`. Verify model artifacts by content hash, including the required audio projector, rather than relying on mutable names.

Use LLMKube's existing routing, with limited access under the cluster's default-deny policies. This service is not a member of a ModelPool. Repository commit `64b6236b5` documents that the GTX 1060 was removed from `sinon`. The shared NVIDIA device-plugin resource still provides generic GPU scheduling rather than selecting a T4. The serving container therefore checks that exactly one visible GPU is a Tesla T4 and fails closed before loading model weights if the check fails. Verify the live hardware inventory, allocation, and startup guard before relying on the service. Keep the service internal and restrict model-download egress to the required destinations. Retain the cluster's workload hardening where compatible with GPU access. This decision does not establish a public voice-cloning service or a data-retention policy.

## Alternatives considered

- Leave the current deployment unchanged: avoids GPU contention and additional attack surface but provides no requested local speech service.
- Use the original Qwen implementation with a dedicated Python inference server: retains the upstream model runtime but adds a separate serving stack and its operational and supply-chain burden.
- Run a CPU-only service or use another accelerator: avoids tying the service to the T4 but has unverified performance or requires a different GPU runtime and competes with existing workloads.

## Consequences

LLMKube provides a familiar internal routing and lifecycle boundary, while CUDA and the GGUF conversion introduce compatibility and quantization dependencies. The pinned revision and image improve reproducibility but require explicit updates and vulnerability review. The model and its audio components must be present and compatible; the runtime documentation alone does not prove that the pinned image, CUDA driver, T4, and LLMKube speech routing work together. Verify actual audio output, model loading, GPU allocation, readiness, and routing before relying on the service; GPU memory use and latency remain unknown.

GPU scheduling or time-slicing can contend with existing workloads and does not itself guarantee memory isolation or availability. Node failure makes this single-node service unavailable. Treat prompts, reference voices, and generated audio as sensitive; limit authorized callers and avoid unnecessary logging or persistence. Internal routing and network controls do not by themselves encrypt in-cluster HTTP. Removing the service and its routing restores the prior behavior; downloaded cache data may need separate cleanup according to its storage policy.

## References

- [Existing LLMKube models and pools](../../kube/deploy/apps/llmkube/models/common.yaml)
- [LLMKube network policy](../../kube/deploy/apps/llmkube/app/netpol.yaml)
- [Pinned GGUF model revision](https://huggingface.co/ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF/tree/ca27d74bc954b73dadab5b71ca265d87fc861a7c)
- [llama.cpp b12602 text-to-speech documentation](https://github.com/ggml-org/llama.cpp/blob/b12602/docs/multimodal/tts.md)
- [llama.cpp b12602 server API](https://github.com/ggml-org/llama.cpp/blob/b12602/tools/server/README.md)
