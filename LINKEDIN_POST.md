I built a local RAG pipeline in n8n this week (LM Studio, Gemma-4-12B, Qwen3 embeddings). But the interesting part wasn't the RAG system. It was how I built it.

I've stopped using one AI model to write and grade its own homework. Instead:

→ Haiku scaffolded the workflow: 7 nodes, webhook to embedding to retrieval to generation, plus the docs.
→ Fable ran QA on it, adversarial, model-agnostic, poking at edge cases.
→ I (with Sonnet) verified against ground truth by actually hitting the endpoints.

That last step mattered. Here's what surfaced only when I ran it for real:

- The workflow was wired to Ollama on port 11434. My models were loaded in LM Studio on port 1234. Different runtime, different API shape, silent failure.
- The webhook used "respond immediately" mode, so it would ack the request and never return the generated answer.
- The input parser read the payload at the wrong nesting level. Every request would've thrown "question required" even with a valid question.
- Data got dropped between nodes: citations and source context vanished before the final response, so the model's answer would have looked ungrounded even when it wasn't.
- Gemma-4-12B reasons before it answers. With a tight token budget, it burned the whole budget thinking and returned an empty string. Looked like a bug. Was actually a config number.

None of these show up in a review of the JSON. They show up when you send a real request and read the real response.

The methodology I'm settling into: one model to build fast, a second model to attack it from a different angle, and a human (plus a third model) to confirm against the actual system, not the code that describes the system. Three roles, three blind spots covered.

The output: a fully local, zero-API-cost RAG pipeline running end-to-end in about 8 seconds, cited answers, no cloud dependency.

The lesson: AI-assisted build velocity is real. AI-assisted verification without touching the real system is theater.

How are others structuring QA when the builder is an AI model too?

#AIEngineering #RAG #n8n #LocalLLM #AgenticWorkflows
