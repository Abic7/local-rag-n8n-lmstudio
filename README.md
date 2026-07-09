# local-rag-n8n-lmstudio

A fully local RAG (Retrieval-Augmented Generation) pipeline built in n8n, running entirely against [LM Studio](https://lmstudio.ai) — no cloud API, no per-query cost, no data leaving the machine.

- **LLM:** `google/gemma-4-12b`
- **Embeddings:** `text-embedding-qwen3-embedding-8b`
- **Orchestration:** n8n (7-node workflow)
- **Runtime:** [LM Studio](https://lmstudio.ai)'s OpenAI-compatible local API (`http://127.0.0.1:1234`)

## Why this exists

Most RAG walkthroughs assume a cloud API key. This one doesn't — every embedding call and every generation call hits a model running on your own hardware. The trade-off is latency (seconds, not milliseconds) for zero marginal cost and zero data exposure.

It also doubles as a worked example of a build methodology: one model scaffolds the workflow, a second attacks it as an adversarial reviewer, and a human plus a third model verify it against the real running system. See [`LINKEDIN_POST.md`](LINKEDIN_POST.md) and the animation at [`video/methodology-animation.html`](video/methodology-animation.html) for that story — five real bugs only surfaced once someone actually hit the live endpoint (wrong port, a webhook that never returned its answer, a payload read at the wrong nesting depth, dropped citation data between nodes, and a reasoning model that silently ran out of its token budget).

## Quick start

1. Install [LM Studio](https://lmstudio.ai), load `google/gemma-4-12b` and `text-embedding-qwen3-embedding-8b`, and start its local server (Developer tab → Start Server, default port `1234`).
2. Import [`rag-workflow.json`](rag-workflow.json) into a running n8n instance.
3. Activate the workflow.
4. Send a request:

   ```bash
   curl -X POST http://localhost:5678/webhook/rag \
     -H "Content-Type: application/json" \
     -d '{"question": "What are architectural considerations?"}'
   ```

   Expect a `200` with a cited answer in roughly 7–10 seconds on a single consumer GPU.

If n8n runs inside Docker, swap `127.0.0.1` for `host.docker.internal` in the two Code nodes that call LM Studio (`Embed Query` and `Generate Answer`) — a container can't reach the host's localhost directly.

## Repository layout

| File | What it is |
|---|---|
| [`rag-workflow.json`](rag-workflow.json) | The n8n workflow — import this to run it |
| [`RAG_ARCHITECTURE.md`](RAG_ARCHITECTURE.md) | The 5-stage pipeline explained in depth |
| [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md) | Node-by-node config, testing, production notes |
| [`LOCAL_MODELS_SETUP.md`](LOCAL_MODELS_SETUP.md) | Model selection, GPU acceleration, troubleshooting |
| [`SETUP_CHECKLIST.md`](SETUP_CHECKLIST.md), [`QUICK_REFERENCE.txt`](QUICK_REFERENCE.txt) | Background context, not required to run the pipeline |

## How it works

```
Webhook → Validate Input → Embed Query (Qwen3) → Retrieve Chunks
        → Build RAG Prompt → Generate Answer (Gemma) → Format Response
```

Retrieval in this repo is a mocked, similarity-scored stub — the point of the demo is the embedding/generation/verification pattern, not a production vector database. Swapping the `Retrieve Chunks` node for a real Qdrant or Pinecone query is a single-node change; everything upstream (the real embedding) and downstream (prompt construction, citation formatting) is already wired for it.

## License

MIT — see [`LICENSE`](LICENSE).
