# RAG System Architecture Showcase

**Purpose:** Complete production RAG pipeline in n8n for Woods Bagot interview demonstration.

**Date Created:** July 9, 2026

---

## RAG Pipeline Overview

This workflow demonstrates a complete **Retrieval-Augmented Generation (RAG)** system with 5 core stages:

```
Stage 1: Document Ingestion → Stage 2: Chunking → Stage 3: Embedding → Stage 4: Vector Storage → Stage 5: Retrieval & Generation
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      RAG PIPELINE STAGES                        │
└─────────────────────────────────────────────────────────────────┘

STAGE 1: DOCUMENT INGESTION
├─ Input: PDF/Text files via HTTP or local file system
├─ Processing: Extract raw text, metadata, source tracking
└─ Output: Raw document chunks with metadata

STAGE 2: TEXT CHUNKING
├─ Strategy: Sliding window (512 tokens, 50 overlap)
├─ Logic: Split by sentences, maintain context
└─ Output: Numbered chunks with position tracking

STAGE 3: EMBEDDING GENERATION
├─ Provider: OpenAI (text-embedding-3-small) or Ollama (local)
├─ Model: 1536-dim vectors
├─ Processing: Batch embed for performance
└─ Output: Chunks with embeddings + metadata

STAGE 4: VECTOR STORAGE & INDEXING
├─ Backend: Qdrant (Docker local) or Pinecone (cloud)
├─ Operations: Upsert chunks into collection
├─ Indexing: Cosine similarity
└─ Storage: Persistent vector index

STAGE 5: RETRIEVAL & GENERATION
├─ Query Processing:
│  ├─ User question → embed
│  ├─ Cosine similarity search (top-k=5)
│  └─ Retrieve ranked results with scores
├─ Generation:
│  ├─ Format context window: sources + chunks
│  ├─ Prompt engineering: RAG-specific system prompt
│  └─ LLM call: Claude/GPT with grounding
└─ Output: Answer + citations

```

---

## Stage-by-Stage Breakdown

### STAGE 1: Document Ingestion

**Purpose:** Load documents and extract raw content

**Nodes Used:**
- `HTTP Request` (trigger via POST) or `File Read` node
- Metadata extraction: filename, upload date, source URL
- Text extraction: PDF → text conversion

**Configuration:**
```json
{
  "trigger": "webhookPost",
  "acceptedFileTypes": [".pdf", ".txt", ".docx"],
  "maxFileSize": "50MB",
  "outputFormat": {
    "content": "string",
    "filename": "string",
    "uploadedAt": "timestamp",
    "sourceUrl": "string"
  }
}
```

**Success Criteria:**
- Document loaded with content intact
- Metadata captured for traceability
- File validation (size, type, encoding)

---

### STAGE 2: Text Chunking

**Purpose:** Split documents into overlapping chunks to fit LLM context windows

**Algorithm:**
```
Input: Raw document text, target_chunk_size (512 tokens), overlap (50 tokens)

1. Split by sentences (preserve semantic units)
2. Accumulate sentences into chunks
3. Add 50-token overlap to next chunk
4. Track chunk position and original doc reference
5. Output: Array of chunks with metadata
```

**Why Chunking Matters:**
- LLMs have context windows (Claude: 200K, GPT-4: 8K-128K)
- Overlapping prevents splitting information across chunks
- Sentence boundaries preserve meaning

**Configuration (Code Node - JavaScript):**
```javascript
// Input: msg.content (raw text)
// Output: items (array of chunks)

const text = $input.first().json.content;
const chunkSize = 512;
const overlap = 50;

const sentences = text.match(/[^.!?]+[.!?]+/g) || [text];
const chunks = [];
let currentChunk = "";
let tokenCount = 0;

for (const sentence of sentences) {
  const sentenceTokens = sentence.split(/\s+/).length;
  
  if (tokenCount + sentenceTokens > chunkSize) {
    chunks.push({
      text: currentChunk.trim(),
      chunkId: chunks.length,
      docId: $input.first().json.docId,
      tokenCount: tokenCount,
      createdAt: new Date().toISOString()
    });
    
    currentChunk = sentences.slice(-Math.ceil(overlap/10)).join(" ");
    tokenCount = Math.ceil(overlap/10);
  }
  
  currentChunk += " " + sentence;
  tokenCount += sentenceTokens;
}

if (currentChunk.trim()) {
  chunks.push({
    text: currentChunk.trim(),
    chunkId: chunks.length,
    docId: $input.first().json.docId,
    tokenCount: tokenCount,
    createdAt: new Date().toISOString()
  });
}

return chunks;
```

**Output Format:**
```json
[
  {
    "chunkId": 0,
    "text": "Architecture decisions shape system outcomes...",
    "tokenCount": 512,
    "docId": "doc-001",
    "createdAt": "2026-07-09T10:30:00Z"
  }
]
```

---

### STAGE 3: Embedding Generation

**Purpose:** Convert text chunks into dense vector representations

**Why Embeddings:**
- Enables semantic similarity search (vs. keyword matching)
- Powers vector database indexing
- Bridges text and numerical computation

**Provider Options:**

**Option A: OpenAI (Cloud, Production)**
```
Model: text-embedding-3-small
Dimensions: 1536
Cost: $0.02 per 1M tokens
Batch size: 100 texts per request
```

**Option B: Ollama (Local, Free)**
```
Model: nomic-embed-text (no internet required)
Dimensions: 768
Cost: Free (GPU accelerated)
Batch size: 32 texts per request
Setup: docker run -d -v ollama:/root/.ollama -p 11434:11434 ollama/ollama
       ollama pull nomic-embed-text
```

**n8n Node Configuration:**

For **OpenAI** (Pinecone integration):
```json
{
  "nodeType": "n8n-nodes-base.openaiEmbedding",
  "inputs": {
    "authentication": "credentialType:openaiApi",
    "model": "text-embedding-3-small",
    "input": "{{ $json.text }}"
  },
  "outputs": {
    "embedding": "array of floats (1536-dim)",
    "usage": { "tokens": "number" }
  }
}
```

For **Ollama** (Qdrant integration):
```json
{
  "nodeType": "n8n-nodes-langchain.embeddingsOllama",
  "inputs": {
    "baseUrl": "http://localhost:11434",
    "model": "nomic-embed-text",
    "stripNewLines": true
  },
  "outputs": {
    "embedding": "array of floats (768-dim)"
  }
}
```

**Batch Processing Logic:**
```javascript
// Code node: batch chunks into groups of 32-100 for efficient API calls
const chunks = $input.first().json;
const batchSize = 32;
const batches = [];

for (let i = 0; i < chunks.length; i += batchSize) {
  batches.push(chunks.slice(i, i + batchSize));
}

return batches;
```

**Output Format:**
```json
{
  "chunkId": 0,
  "text": "Architecture decisions shape system outcomes...",
  "embedding": [0.123, -0.456, 0.789, ...],  // 1536 or 768 dims
  "docId": "doc-001",
  "embeddingModel": "text-embedding-3-small",
  "createdAt": "2026-07-09T10:30:00Z"
}
```

---

### STAGE 4: Vector Storage & Indexing

**Purpose:** Store embeddings in vector database for fast retrieval

**Database Options:**

**Option A: Qdrant (Local, Open Source)**
```
Setup: docker run -p 6333:6333 qdrant/qdrant
Pros: Self-hosted, no API keys, HNSW indexing, 100ms queries
Cons: Requires Docker, database management
Collection: "documents" with similarity: "Cosine", size: 768
```

**Option B: Pinecone (Cloud SaaS)**
```
Setup: API key from pinecone.io
Pros: Fully managed, scales to billions, no infrastructure
Cons: $0.25/hour always-on, vendor lock-in
Index: "documents" with dimension 1536, similarity: "cosine"
```

**n8n Node Configuration:**

For **Qdrant**:
```json
{
  "nodeType": "n8n-nodes-base.vectorStorageQdrant",
  "operation": "upsert",
  "inputs": {
    "url": "http://localhost:6333",
    "collectionName": "documents",
    "points": [
      {
        "id": "chunk-001",
        "vector": [0.123, -0.456, ...],
        "payload": {
          "chunkId": 0,
          "text": "...",
          "docId": "doc-001",
          "createdAt": "2026-07-09T10:30:00Z"
        }
      }
    ]
  }
}
```

For **Pinecone**:
```json
{
  "nodeType": "n8n-nodes-base.vectorStoragePinecone",
  "operation": "upsert",
  "inputs": {
    "credential": "pineconeApi",
    "indexName": "documents",
    "vectors": [
      {
        "id": "chunk-001",
        "values": [0.123, -0.456, ...],
        "metadata": {
          "chunkId": 0,
          "text": "...",
          "docId": "doc-001"
        }
      }
    ]
  }
}
```

**Storage Metrics:**
- Total vectors: 5,000 chunks × ~1,536 dims = ~7.6M floats
- Storage per vector: 6 KB (float32) + 0.5 KB metadata
- Total DB size: ~35 GB (uncompressed), ~5 GB (compressed)
- Query latency: 50-150ms (Qdrant local), 200-500ms (Pinecone)

---

### STAGE 5: Retrieval & Generation

**Purpose:** Answer user questions using retrieved context

**Retrieval Flow:**
```
1. User Question: "What are the key architectural considerations?"
   ↓
2. Embedding: Query → embed (1536 dims)
   ↓
3. Similarity Search: Cosine distance to all stored vectors
   ↓
4. Ranking: Top-k=5 results sorted by similarity score
   ↓
5. Context Retrieval: Return chunks + metadata
   ↓
6. Prompt Construction: User question + context + instructions
   ↓
7. LLM Generation: Claude API with grounding
   ↓
8. Output: Answer + citations (chunk IDs, similarity scores)
```

**n8n Nodes:**

**A. Query Embedding (same as Stage 3):**
```json
{
  "nodeType": "n8n-nodes-base.openaiEmbedding",
  "inputs": {
    "model": "text-embedding-3-small",
    "input": "{{ $json.question }}"
  },
  "outputs": {
    "embedding": "array"
  }
}
```

**B. Vector Retrieval (Qdrant example):**
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
  },
  "outputs": {
    "results": [
      {
        "id": "chunk-001",
        "score": 0.89,
        "payload": {
          "text": "...",
          "chunkId": 0,
          "docId": "doc-001"
        }
      }
    ]
  }
}
```

**C. Prompt Construction (Code Node):**
```javascript
// Build context-aware prompt for LLM
const question = $input.first().json.question;
const results = $input.first().json.retrievalResults;

const contextText = results
  .map((r, i) => `[Source ${i+1}] (Similarity: ${(r.score*100).toFixed(1)}%)\n${r.payload.text}`)
  .join("\n\n");

const systemPrompt = `You are an expert AI assistant specializing in architecture and design systems. 
You have access to internal documentation and must always cite your sources.
Format citations as [Source N] and explain your reasoning.`;

const userPrompt = `Based on the following documentation:

${contextText}

Question: ${question}

Provide a detailed, well-reasoned answer citing specific sections.`;

return {
  systemPrompt,
  userPrompt,
  sources: results
};
```

**D. LLM Generation (Claude/OpenAI):**
```json
{
  "nodeType": "n8n-nodes-base.openaiChat",
  "inputs": {
    "model": "gpt-4o or claude-opus-4-1",
    "systemMessage": "{{ $json.systemPrompt }}",
    "prompt": "{{ $json.userPrompt }}",
    "temperature": 0.3,
    "maxTokens": 1024
  },
  "outputs": {
    "response": "generated text with citations"
  }
}
```

**E. Response Formatting:**
```javascript
// Final output: answer + metadata
const answer = $input.first().json.response;
const sources = $input.first().json.sources;

return {
  answer: answer,
  citations: sources.map(s => ({
    chunkId: s.payload.chunkId,
    docId: s.payload.docId,
    similarity: s.score,
    text: s.payload.text.substring(0, 200) + "..."
  })),
  generatedAt: new Date().toISOString(),
  model: "gpt-4o",
  tokensUsed: {
    prompt: 1200,
    completion: 340
  }
};
```

---

## Complete Flow Summary

| Stage | Input | Processing | Output | Tools |
|-------|-------|-----------|--------|-------|
| 1. Ingestion | Files/URLs | Extract text + metadata | Raw text, metadata | HTTP, File node |
| 2. Chunking | Raw text | Split on sentences, overlap | Chunks (512 tokens) | Code node (JS) |
| 3. Embedding | Chunks | Convert to vectors | Dense vectors (1536-dim) | OpenAI/Ollama |
| 4. Storage | Vectors + metadata | Index and upsert | Searchable DB | Qdrant/Pinecone |
| 5. Retrieval | User question | Embed query, search, rank | Top-5 chunks + answer | OpenAI Embed + LLM |

---

## Production Deployment Checklist

- [ ] **Vector Database:** Qdrant Docker container running, persistent volume mounted
- [ ] **Embeddings:** OpenAI API key configured (or Ollama local endpoint)
- [ ] **LLM:** Claude API key configured
- [ ] **Monitoring:** Track query latency, cache hit rate, cost per query
- [ ] **Scaling:** Batch embed processing, connection pooling
- [ ] **Security:** API keys in n8n credentials (not hardcoded), rate limiting on endpoints
- [ ] **Data Quality:** Duplicate detection, chunk validation, source tracking
- [ ] **Versioning:** Store embedding model version, chunk size in metadata

---

## Performance Targets

- **End-to-end latency:** <3 seconds (embed query: 500ms, search: 150ms, LLM generation: 2s)
- **Query throughput:** 10+ queries/second (with caching)
- **Embedding cost:** ~$0.03 per 1M tokens (OpenAI)
- **Vector search accuracy:** >85% top-5 recall (relevance)
- **Update latency:** <1 second (new chunks indexed)

---

## Interview Talking Points

1. **RAG vs. Fine-tuning:** RAG is faster (no retraining), cheaper (no token overhead), and more flexible (swap documents dynamically).

2. **Chunking Strategy:** Semantic chunks with overlap prevent information loss at boundaries. Tunable: 256-1024 tokens based on domain.

3. **Embedding Model Selection:** Small models (nomic-embed, text-small) trade 1% accuracy for 10x speed. We use scoring thresholds to filter low-confidence matches.

4. **Vector Database Trade-offs:**
   - **Qdrant (local):** Full control, no costs, but operations overhead
   - **Pinecone (cloud):** Managed scaling, but $0.25/hour baseline

5. **Generation Grounding:** System prompt explicitly requires source citations. LLM tokens are 3-5x cheaper than if you retrained on this data.

6. **Monitoring:** Track similarity scores of retrieved chunks. Low scores = query-document mismatch. High scores = high confidence.

7. **Failure Modes:** 
   - Empty retrieval (no relevant chunks) → graceful degradation to LLM-only
   - Noisy context (irrelevant chunks) → scoring threshold tuning
   - Hallucination + wrong citations → validate LLM outputs against actual sources

---

## Quick Start Commands

**Local Setup (Qdrant):**
```bash
# Start Qdrant vector database
docker run -p 6333:6333 qdrant/qdrant

# Start Ollama embeddings (optional, if not using OpenAI)
docker run -d -p 11434:11434 ollama/ollama
ollama pull nomic-embed-text
```

**n8n Workflow Upload:**
1. Import `rag-workflow.json` into n8n
2. Configure credentials: OpenAI API key, Qdrant URL
3. Trigger: POST `/webhook/rag-chat` with `{ "question": "..." }`
4. Response: `{ "answer": "...", "citations": [...], "generatedAt": "..." }`

---

**Document Version:** 1.0 (July 9, 2026)
**Status:** Ready for interview demonstration
