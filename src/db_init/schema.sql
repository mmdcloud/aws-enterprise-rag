-- ==============================================================================
-- Enterprise RAG Schema: Aurora PostgreSQL 16 with pgvector Extension
-- ==============================================================================

-- 1. Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Master Document Tracking Table
CREATE TABLE IF NOT EXISTS documents (
    document_id VARCHAR(64) PRIMARY KEY,
    source_uri TEXT NOT NULL,
    total_chunks INTEGER NOT NULL DEFAULT 0,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Document Vector Chunks Table
-- Embedding dimension matches Titan Text Embeddings v2 (1024 dimensions)
CREATE TABLE IF NOT EXISTS document_chunks (
    chunk_id VARCHAR(64) PRIMARY KEY,
    document_id VARCHAR(64) NOT NULL REFERENCES documents(document_id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    chunk_text TEXT NOT NULL,
    token_count INTEGER NOT NULL DEFAULT 0,
    metadata JSONB DEFAULT '{}'::jsonb,
    embedding vector(1024) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. High-Performance HNSW Vector Index for Sub-Millisecond Cosine Similarity
-- Cosine distance operator is <=> (using vector_cosine_ops)
-- m=16, ef_construction=64 provides optimal recall-speed trade-off for enterprise datasets
CREATE INDEX IF NOT EXISTS idx_chunks_hnsw_cosine
ON document_chunks
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- 5. Foreign Key and Metadata GIN Indexes
CREATE INDEX IF NOT EXISTS idx_chunks_document_id
ON document_chunks (document_id);

CREATE INDEX IF NOT EXISTS idx_chunks_metadata_gin
ON document_chunks
USING gin (metadata);
