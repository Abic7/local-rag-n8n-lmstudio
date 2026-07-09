# n8n RAG Workflow - Deployment & Testing Guide

**Prepared for:** Woods Bagot Interview Demonstration
**Date:** July 9, 2026

---

## Quick Start (5 Minutes)

### Prerequisites

1. **n8n running** (Docker or local)
   ```bash
   docker run -it --rm \
     -p 5678:5678 \
     -e DB=sqlite \
     n8n/n8n
   ```

2. **OpenAI API key** (for LLM generation)
   - Get from: https://platform.openai.com/api-keys
   - Cost: ~$0.005 per query (using gpt-4o-mini)

3. **Optional: Vector database**
   - Local Qdrant: `docker run -p 6333:6333 qdrant/qdrant`
   - Or use managed Pinecone: https://www.pinecone.io

### Deploy Steps

1. **Open n8n:** http://localhost:5678
2. **Create new workflow** → Import JSON
3. **Paste `rag-workflow.json`** into workflow editor
4. **Add OpenAI credential:**
   - Sidebar → Credentials
   - New → OpenAI
   - Paste API key
5. **Test webhook endpoint:**
   ```bash
   curl -X POST http://localhost:5678/webhook/rag \
     -H "Content-Type: application/json" \
     -d '{"question": "What are architectural considerations?"}'
   ```

---

## Workflow Architecture

```
INPUT (Webhook)
    ↓
[Validate Input] — Check question not empty
    ↓
[Embed Query] — Convert question to vector (1536-dim)
    ↓
[Retrieve Chunks] — Mock search (production: Qdrant/Pinecone)
    ↓
[Build RAG Prompt] — Construct context window with sources
    ↓
[Generate Answer] — Call OpenAI GPT-4o-mini
    ↓
[Format Response] — Return answer + citations + metadata
    ↓
OUTPUT (JSON response)
```

---

## Node-by-Node Configuration

### 1. Webhook Trigger

**Purpose:** Accept incoming questions via HTTP POST

**Configuration:**
```
Path: /rag
Method: POST
Response Mode: On Received (immediate ACK)
```

**Test Request:**
```bash
curl -X POST http://localhost:5678/webhook/rag \
  -H "Content-Type: application/json" \
  -d '{
    "question": "What are the key architectural decisions?",
    "docId": "doc-001"
  }'
```

**Expected Output:**
```json
{
  "status": "success",
  "question": "What are the key architectural decisions?",
  "answer": "Architecture decisions shape system outcomes...",
  "citations": [
    {
      "sourceId": 1,
      "chunkId": 1,
      "similarity": 0.92
    }
  ]
}
```

---

### 2. Validate Input

**Purpose:** Ensure question is present and non-empty

**JavaScript Code Node:**
```javascript
const input = $input.first().json;

const validation = {
  question: input.question || '',
  docId: input.docId || 'doc-' + Date.now(),
  uploadedAt: new Date().toISOString()
};

if (!validation.question || validation.question.trim().length === 0) {
  throw new Error('Question is required');
}

return { ...input, ...validation };
```

**Error Handling:**
- Missing `question` field → throws error, workflow stops
- Empty string → throws error
- Valid question → continues to next node

---

### 3. Embed Query

**Purpose:** Convert user question into embedding vector

**Current Implementation:** Mock embedding (deterministic from question text)

**Production Implementation:** Replace with OpenAI or Ollama

#### Option A: OpenAI Embedding Node
```json
{
  "nodeType": "n8n-nodes-base.openaiEmbedding",
  "inputs": {
    "model": "text-embedding-3-small",
    "input": "{{ $json.question }}",
    "endpoint": "https://api.openai.com"
  }
}
```

**Cost:** $0.02 per 1M tokens (~$0.000002 per question)

#### Option B: Local Ollama
```json
{
  "nodeType": "n8n-nodes-langchain.embeddingsOllama",
  "inputs": {
    "baseUrl": "http://localhost:11434",
    "model": "nomic-embed-text"
  }
}
```

**Setup:**
```bash
docker run -d -p 11434:11434 ollama/ollama
ollama pull nomic-embed-text
```

**Current Mock Logic:**
```javascript
const hash = question.split('').reduce((h, c) => h + c.charCodeAt(0), 0);
const seed = hash % 1000;

const embedding = Array.from({ length: 1536 }, (_, i) => {
  const pseudo = Math.sin(seed + i) * 0.5 + 0.5;
  return parseFloat((pseudo * 2 - 1).toFixed(6));
});
```

---

### 4. Retrieve Chunks

**Purpose:** Search vector database for similar chunks

**Current Implementation:** Mock retrieval with 3 sample documents

**Production Implementation:** Query Qdrant or Pinecone

#### Option A: Qdrant Retrieval
```json
{
  "nodeType": "n8n-nodes-base.vectorStorageQdrant",
  "operation": "query",
  "inputs": {
    "url": "http://localhost:6333",
    "collectionName": "documents",
    "vector": "{{ $json.embedding }}",
    "limit": 5,
    "scoreThreshold": 0.7
  }
}
```

**Setup:**
```bash
docker run -p 6333:6333 qdrant/qdrant
```

#### Option B: Pinecone Retrieval
```json
{
  "nodeType": "n8n-nodes-base.vectorStoragePinecone",
  "operation": "query",
  "inputs": {
    "credential": "pineconeApi",
    "indexName": "documents",
    "vector": "{{ $json.embedding }}",
    "topK": 5,
    "filter": "{{ {metadata_filter: $json.docId} }}"
  }
}
```

**Mock Data (Current):**
```javascript
const mockDocuments = [
  {
    chunkId: 1,
    similarity: 0.92,
    text: "Architecture decisions shape system outcomes..."
  },
  {
    chunkId: 2,
    similarity: 0.87,
    text: "Automation frameworks reduce manual effort..."
  },
  {
    chunkId: 3,
    similarity: 0.81,
    text: "AI systems require careful evaluation..."
  }
];
```

---

### 5. Build RAG Prompt

**Purpose:** Construct context window with retrieved chunks + user question

**Output Structure:**
```javascript
{
  systemPrompt: "You are an expert AI assistant...",
  userPrompt: "Based on the following documentation:\n\n[Sources]\n\nQuestion: ...",
  sources: [/* chunk objects */],
  question: "..."
}
```

**System Prompt Pattern:**
```
You are an expert AI assistant specializing in [DOMAIN].
You have access to internal documentation and must always cite your sources using [Source N] format.
Provide detailed, well-reasoned answers grounded in the provided context.
```

**User Prompt Pattern:**
```
Based on the following documentation:

[Source 1] (Similarity: 92.0%)
<chunk text>

[Source 2] (Similarity: 87.0%)
<chunk text>

Question: <user question>

Provide a detailed answer citing specific sections.
```

---

### 6. Generate Answer (LLM)

**Purpose:** Call Claude/GPT with RAG context

#### OpenAI Configuration (Current)
```json
{
  "nodeType": "n8n-nodes-base.openaiChat",
  "method": "create",
  "model": "gpt-4o-mini",
  "messages": [
    {
      "role": "system",
      "content": "{{ $json.systemPrompt }}"
    },
    {
      "role": "user",
      "content": "{{ $json.userPrompt }}"
    }
  ],
  "options": {
    "temperature": 0.3,
    "maxTokens": 1024
  }
}
```

**Models Comparison:**
| Model | Speed | Cost | Quality |
|-------|-------|------|---------|
| gpt-4o-mini | Fast | $0.0005/1K | Good |
| gpt-4o | Medium | $0.03/1K | Excellent |
| gpt-4-turbo | Medium | $0.01/1K | Excellent |
| claude-opus | Slow | $0.015/1K | Best |

**Temperature Tuning:**
- 0.0-0.3: Deterministic, grounded answers (recommended for RAG)
- 0.5-0.7: Balanced, creative responses
- 0.8-1.0: Creative, high-variance outputs

#### Anthropic Claude Alternative
To use Claude instead of GPT-4o:

```json
{
  "nodeType": "n8n-nodes-base.anthropicChat",
  "model": "claude-opus-4-1",
  "messages": [
    {
      "role": "user",
      "content": "{{ $json.userPrompt }}"
    }
  ],
  "systemPrompt": "{{ $json.systemPrompt }}",
  "options": {
    "temperature": 0.3,
    "maxTokens": 1024
  }
}
```

---

### 7. Format Response

**Purpose:** Shape output for API consumer + add metadata

**Output Schema:**
```json
{
  "status": "success",
  "question": "user's original question",
  "answer": "generated response with citations",
  "citations": [
    {
      "sourceId": 1,
      "chunkId": "chunk-001",
      "similarity": 0.92,
      "preview": "first 150 chars of chunk..."
    }
  ],
  "metadata": {
    "generatedAt": "2026-07-09T10:30:00Z",
    "model": "gpt-4o-mini",
    "retrievalCount": 3,
    "pipeline": "RAG (Retrieval-Augmented Generation)",
    "version": "1.0"
  }
}
```

---

## Testing Scenarios

### Test 1: Basic Question

**Input:**
```json
{
  "question": "What are architectural considerations?"
}
```

**Expected Output:** Answer + 3 citations about architecture

**Command:**
```bash
curl -X POST http://localhost:5678/webhook/rag \
  -H "Content-Type: application/json" \
  -d '{"question": "What are architectural considerations?"}'
```

---

### Test 2: Automation-Focused Question

**Input:**
```json
{
  "question": "How do automation frameworks improve efficiency?"
}
```

**Expected Output:** Answer + 3 citations mentioning automation

---

### Test 3: Error Handling (Empty Question)

**Input:**
```json
{
  "question": ""
}
```

**Expected Output:** Error response (validation should catch this)

---

## Production Configuration

### A. Local Vector Database (Qdrant)

**Pros:**
- Full control, no vendor lock-in
- Cheap to run (free software)
- Predictable latency

**Cons:**
- Operations overhead (backups, monitoring)
- Manual scaling

**Docker Compose Setup:**
```yaml
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant_db
    ports:
      - "6333:6333"
    volumes:
      - ./qdrant_storage:/qdrant/storage
    environment:
      QDRANT_API_KEY: "your-api-key-here"

  n8n:
    image: n8n/n8n:latest
    depends_on:
      - qdrant
    ports:
      - "5678:5678"
    environment:
      - DB=sqlite
    volumes:
      - ./n8n_data:/home/node/.n8n
```

### B. Managed Vector Database (Pinecone)

**Pros:**
- Fully managed, no ops
- Automatic scaling
- Built-in monitoring

**Cons:**
- $0.25/hour baseline
- Vendor lock-in
- Cold startup latency

**Configuration:**
1. Create account at pinecone.io
2. Create index: `documents` (dimension: 1536, similarity: cosine)
3. Add credential to n8n with API key
4. Replace Qdrant node with Pinecone node

---

## Monitoring & Observability

### Metrics to Track

**Latency Breakdown:**
- Embedding generation: 200-500ms
- Vector search: 50-150ms
- LLM generation: 1-3 seconds
- Total: 2-4 seconds

**Quality Metrics:**
- Retrieved chunk similarity scores (target: >0.75)
- Answer accuracy (human evaluation)
- Citation correctness (sources match content)

### n8n Monitoring

**Enable Execution History:**
1. Workflow Settings → Save Execution Data
2. Logs tab shows each node's output
3. Export failed executions for debugging

**Example Check:**
```bash
# View workflow executions via n8n API
curl -X GET http://localhost:5678/api/v1/executions?workflowId=<id> \
  -H "X-N8N-API-KEY: <your-key>"
```

---

## Common Issues & Fixes

### Issue 1: OpenAI API Key Invalid

**Symptom:** "OpenAI Authentication Failed"

**Fix:**
1. Verify API key format (starts with `sk-`)
2. Check key has API access enabled
3. Confirm billing is active

---

### Issue 2: Vector Similarity Too Low

**Symptom:** Irrelevant chunks retrieved (similarity < 0.5)

**Causes & Fixes:**
- Question and documents in different domains → add more relevant docs
- Embeddings outdated → re-embed with same model
- Chunk size too large → re-chunk with smaller window

---

### Issue 3: Hallucination (Answer contradicts sources)

**Symptom:** LLM generates unsupported claims

**Fixes:**
1. Lower temperature (0.1 instead of 0.3)
2. Add validation: compare answer against citations
3. Require explicit citations: `Answer must cite [Source N]`

---

## Performance Optimization

### Caching Layer

Add Redis cache before LLM generation:

```json
{
  "nodeType": "n8n-nodes-base.redis",
  "operation": "getFromRedis",
  "key": "{{ $json.question }}"
}
```

**Hit rate target:** 30-40% for repeated questions

### Batch Processing

Process multiple questions in parallel:

```json
{
  "nodeType": "n8n-nodes-base.splitInBatches",
  "batchSize": 10
}
```

### Connection Pooling

For Qdrant/Pinecone:
- Keep connections alive between queries
- Reuse embeddings API client

---

## Interview Demo Script

### Setup (5 min before)
1. Start n8n: `docker run -p 5678:5678 n8n/n8n`
2. Import workflow
3. Add OpenAI credential
4. Test one query to verify

### Demo Flow (15 minutes)

**Slide 1: Problem Statement** (2 min)
> "Enterprises have massive documentation but no way to query it. Fine-tuning is slow and expensive. RAG solves this by retrieving relevant context and grounding LLM answers in actual sources."

**Slide 2: Architecture** (3 min)
> Walk through each stage:
> - Documents → chunks (overlapping windows)
> - Chunks → embeddings (semantic vectors)
> - Embeddings → vector DB (fast search)
> - Query → retrieve → generate (grounded answer)

**Slide 3: Live Demo** (7 min)
1. Send test query via curl
2. Show workflow execution in n8n UI
3. Highlight retrieval step (which chunks came back)
4. Show LLM generating answer with citations
5. Display final JSON response with metadata

**Slide 4: Key Insights** (3 min)
- RAG accuracy depends on chunk quality (demo the overlap strategy)
- Embeddings are semantic (show similar questions retrieving same docs)
- Cost is dominated by LLM tokens, not vector search
- Temperature tuning prevents hallucination

**Q&A:** "How would you handle multi-language?" / "Scale to 10M documents?" / "Reduce latency to <1s?"

---

## Next Steps

### Short-term (This Week)
- [ ] Deploy to real n8n instance
- [ ] Connect to actual vector database (Qdrant or Pinecone)
- [ ] Load real documents and generate embeddings

### Medium-term (This Month)
- [ ] Add document upload API endpoint
- [ ] Implement cache layer (Redis)
- [ ] Set up monitoring dashboard

### Long-term (Production)
- [ ] Multi-tenant architecture (separate collections per org)
- [ ] Fine-tune embedding model on domain data
- [ ] Implement reranking (second-pass relevance scoring)
- [ ] Add feedback loop (track which answers were helpful)

---

**Last Updated:** July 9, 2026
**Status:** Ready for interview demo
