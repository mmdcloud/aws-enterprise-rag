"""Amazon ElastiCache Redis Semantic Caching Engine."""

import hashlib
import json
import time
from typing import Any, Dict, List, Optional, Tuple
import numpy as np
import redis

from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.models import Citation, QueryResponse, SemanticCacheEntry

logger = get_logger(__name__)


class RedisSemanticCache:
    """Production Semantic Cache for Enterprise RAG queries using ElastiCache Redis.

    Supports:
    1. Exact query hash lookup (O(1) <1ms).
    2. Vector cosine similarity search over cached query embeddings.
    3. Automatic TTL expiration and LRU cache eviction.
    """

    EXACT_PREFIX = "rag:cache:exact:"
    SEMANTIC_SET = "rag:cache:index:queries"
    ENTRY_PREFIX = "rag:cache:entry:"

    def __init__(
        self,
        endpoint: Optional[str] = None,
        port: Optional[int] = None,
        ttl_seconds: Optional[int] = None,
        similarity_threshold: Optional[float] = None,
        redis_client: Optional[redis.Redis] = None,
    ):
        self.endpoint = endpoint or settings.REDIS_ENDPOINT
        self.port = port or settings.REDIS_PORT
        self.ttl = ttl_seconds or settings.SEMANTIC_CACHE_TTL_SECONDS
        self.similarity_threshold = similarity_threshold or settings.SEMANTIC_CACHE_SIMILARITY_THRESHOLD
        self._redis = redis_client

    @property
    def client(self) -> redis.Redis:
        if self._redis is None:
            self._redis = redis.Redis(
                host=self.endpoint,
                port=self.port,
                ssl=settings.REDIS_USE_SSL and settings.ENVIRONMENT != "local",
                password=settings.REDIS_PASSWORD or None,
                decode_responses=False,
                socket_connect_timeout=2,
                socket_timeout=3,
            )
        return self._redis

    def get(
        self,
        query: str,
        query_embedding: List[float],
        threshold: Optional[float] = None,
    ) -> Tuple[bool, Optional[QueryResponse], float]:
        """Looks up the query in semantic cache.

        Returns:
            Tuple of (is_hit: bool, cached_response: Optional[QueryResponse], similarity: float)
        """
        start_time = time.time()
        thresh = threshold or self.similarity_threshold

        # 1. Fast Path: Exact Match Hash
        query_hash = hashlib.sha256(query.strip().lower().encode("utf-8")).hexdigest()
        exact_key = f"{self.EXACT_PREFIX}{query_hash}"

        try:
            cached_entry_raw = self.client.get(exact_key)
            if cached_entry_raw:
                entry = json.loads(cached_entry_raw.decode("utf-8"))
                lookup_latency = (time.time() - start_time) * 1000
                logger.info(f"Cache HIT (Exact match) for query in {lookup_latency:.2f}ms")
                response = QueryResponse(
                    answer=entry["answer"],
                    cached=True,
                    similarity_score=1.0,
                    citations=[Citation(**c) for c in entry.get("citations", [])],
                    latency_ms=lookup_latency,
                    cache_lookup_latency_ms=lookup_latency,
                    generation_latency_ms=0.0,
                    model_id=entry.get("model_id", settings.BEDROCK_LLM_MODEL_ID),
                )
                return True, response, 1.0

            # 2. Semantic Vector Similarity Search
            # Scan active cached query keys
            cached_query_ids = self.client.smembers(self.SEMANTIC_SET)
            if not cached_query_ids:
                lookup_latency = (time.time() - start_time) * 1000
                return False, None, 0.0

            # Compute cosine similarity across cached embeddings
            query_vec = np.array(query_embedding, dtype=np.float32)
            query_norm = np.linalg.norm(query_vec)
            if query_norm > 0:
                query_vec = query_vec / query_norm

            best_similarity = -1.0
            best_entry: Optional[Dict[str, Any]] = None
            expired_keys: List[bytes] = []

            for q_id_bytes in cached_query_ids:
                entry_key = f"{self.ENTRY_PREFIX}{q_id_bytes.decode('utf-8')}"
                entry_data = self.client.get(entry_key)

                if not entry_data:
                    expired_keys.append(q_id_bytes)
                    continue

                cached_obj = json.loads(entry_data.decode("utf-8"))
                cached_vec = np.array(cached_obj["embedding"], dtype=np.float32)
                c_norm = np.linalg.norm(cached_vec)
                if c_norm > 0:
                    cached_vec = cached_vec / c_norm

                similarity = float(np.dot(query_vec, cached_vec))
                if similarity > best_similarity:
                    best_similarity = similarity
                    best_entry = cached_obj

            # Clean expired members in background
            if expired_keys:
                self.client.srem(self.SEMANTIC_SET, *expired_keys)

            lookup_latency = (time.time() - start_time) * 1000

            if best_similarity >= thresh and best_entry is not None:
                logger.info(
                    f"Cache HIT (Semantic match: {best_similarity:.4f} >= {thresh}) in {lookup_latency:.2f}ms"
                )
                response = QueryResponse(
                    answer=best_entry["answer"],
                    cached=True,
                    similarity_score=round(best_similarity, 4),
                    citations=[Citation(**c) for c in best_entry.get("citations", [])],
                    latency_ms=lookup_latency,
                    cache_lookup_latency_ms=lookup_latency,
                    generation_latency_ms=0.0,
                    model_id=best_entry.get("model_id", settings.BEDROCK_LLM_MODEL_ID),
                )
                return True, response, best_similarity

            logger.info(f"Cache MISS (Best similarity: {best_similarity:.4f} < {thresh}) in {lookup_latency:.2f}ms")
            return False, None, best_similarity

        except Exception as e:
            logger.warning(f"Semantic cache lookup error (degraded to cache miss): {e}")
            return False, None, 0.0

    def set(
        self,
        query: str,
        query_embedding: List[float],
        answer: str,
        citations: List[Citation],
        model_id: str,
    ) -> None:
        """Stores a generated query response and its embedding into Redis with TTL."""
        try:
            query_hash = hashlib.sha256(query.strip().lower().encode("utf-8")).hexdigest()
            entry_id = query_hash[:16]

            entry_payload = {
                "query": query,
                "embedding": query_embedding,
                "answer": answer,
                "citations": [c.model_dump(mode="json") for c in citations],
                "model_id": model_id,
                "created_at": time.time(),
            }
            raw_payload = json.dumps(entry_payload)

            pipe = self.client.pipeline()
            # Exact match pointer
            exact_key = f"{self.EXACT_PREFIX}{query_hash}"
            pipe.set(exact_key, raw_payload, ex=self.ttl)

            # Semantic vector entry
            entry_key = f"{self.ENTRY_PREFIX}{entry_id}"
            pipe.set(entry_key, raw_payload, ex=self.ttl)
            pipe.sadd(self.SEMANTIC_SET, entry_id)
            pipe.execute()

            logger.info(f"Stored query in semantic cache with TTL={self.ttl}s (hash={query_hash[:8]})")
        except Exception as e:
            logger.warning(f"Failed to write to semantic cache: {e}")

    def clear(self) -> int:
        """Flushes semantic cache entries."""
        try:
            cached_query_ids = self.client.smembers(self.SEMANTIC_SET)
            keys_to_del = [f"{self.ENTRY_PREFIX}{q.decode('utf-8')}" for q in cached_query_ids]
            keys_to_del.append(self.SEMANTIC_SET)
            if keys_to_del:
                return self.client.delete(*keys_to_del)
            return 0
        except Exception as e:
            logger.error(f"Error clearing cache: {e}")
            return 0


semantic_cache = RedisSemanticCache()
