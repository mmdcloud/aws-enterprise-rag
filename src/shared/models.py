"""Domain models for Enterprise RAG Ingestion and Query Serving."""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field


class DocumentMetadata(BaseModel):
    source_uri: str
    content_type: str
    file_size_bytes: int
    page_count: Optional[int] = None
    title: Optional[str] = None
    ingested_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    custom_metadata: Dict[str, Any] = Field(default_factory=dict)


class DocumentChunk(BaseModel):
    chunk_id: str
    document_id: str
    chunk_index: int
    text: str
    token_count: int
    char_count: int
    metadata: Dict[str, Any] = Field(default_factory=dict)
    embedding: Optional[List[float]] = None


class IngestionJob(BaseModel):
    document_id: str
    bucket: str
    key: str
    status: str = "PENDING"
    chunks_created: int = 0
    pii_entities_found: List[str] = Field(default_factory=list)
    error_message: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class QueryRequest(BaseModel):
    query: str = Field(..., min_length=2, max_length=2000, description="User question or search query")
    filter: Optional[Dict[str, Any]] = Field(default=None, description="Metadata filter (e.g. category, document_id)")
    similarity_threshold: Optional[float] = Field(default=None, ge=0.0, le=1.0, description="Override semantic cache similarity threshold")
    top_k: int = Field(default=5, ge=1, le=20, description="Number of context chunks to retrieve")
    session_id: Optional[str] = None


class Citation(BaseModel):
    document_id: str
    chunk_id: str
    source_uri: str
    score: float
    text_snippet: str
    chunk_index: int


class QueryResponse(BaseModel):
    answer: str
    cached: bool
    similarity_score: Optional[float] = None
    citations: List[Citation] = Field(default_factory=list)
    latency_ms: float
    cache_lookup_latency_ms: float
    generation_latency_ms: Optional[float] = None
    model_id: str
    guardrail_applied: bool = False
    guardrail_action: Optional[str] = None


class SemanticCacheEntry(BaseModel):
    query: str
    embedding: List[float]
    answer: str
    citations: List[Citation]
    model_id: str
    created_at: float
    ttl: int
