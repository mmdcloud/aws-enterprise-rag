"""Unit tests for Redis Semantic Caching Engine."""

import json
import unittest
from typing import Dict, Set
from src.query.semantic_cache import RedisSemanticCache
from src.shared.models import Citation


class MockRedis:
    """In-memory Redis mock for unit testing semantic cache without external server."""

    def __init__(self):
        self.store: Dict[str, bytes] = {}
        self.sets: Dict[str, Set[bytes]] = {}

    def get(self, key: str):
        return self.store.get(key)

    def set(self, key: str, value: str, ex: int = None):
        self.store[key] = value.encode("utf-8") if isinstance(value, str) else value
        return True

    def smembers(self, set_key: str):
        return self.sets.get(set_key, set())

    def sadd(self, set_key: str, *members):
        if set_key not in self.sets:
            self.sets[set_key] = set()
        for m in members:
            self.sets[set_key].add(m.encode("utf-8") if isinstance(m, str) else m)
        return len(members)

    def srem(self, set_key: str, *members):
        if set_key in self.sets:
            for m in members:
                self.sets[set_key].discard(m)

    def delete(self, *keys):
        count = 0
        for k in keys:
            if k in self.store:
                del self.store[k]
                count += 1
            if k in self.sets:
                del self.sets[k]
                count += 1
        return count

    def pipeline(self):
        return self

    def execute(self):
        return True


class TestSemanticCache(unittest.TestCase):

    def setUp(self):
        self.mock_redis = MockRedis()
        self.cache = RedisSemanticCache(
            endpoint="127.0.0.1",
            port=6379,
            ttl_seconds=3600,
            similarity_threshold=0.90,
            redis_client=self.mock_redis,
        )
        # Dummy 1024-dimension unit vectors
        self.v1 = [1.0] + [0.0] * 1023
        self.v1_similar = [0.95, 0.3122] + [0.0] * 1022  # cosine similarity ~ 0.95
        self.v_different = [0.0, 1.0] + [0.0] * 1022     # cosine similarity = 0.0

    def test_cache_miss_when_empty(self):
        is_hit, response, similarity = self.cache.get("What is AWS VPC?", self.v1)
        self.assertFalse(is_hit)
        self.assertIsNone(response)
        self.assertEqual(similarity, 0.0)

    def test_exact_hash_cache_hit(self):
        citations = [
            Citation(
                document_id="doc-1",
                chunk_id="chunk-1",
                source_uri="s3://docs/vpc.pdf",
                score=0.98,
                text_snippet="VPC enables isolated cloud networks.",
                chunk_index=0,
            )
        ]
        self.cache.set(
            query="What is AWS VPC?",
            query_embedding=self.v1,
            answer="AWS VPC is a Virtual Private Cloud.",
            citations=citations,
            model_id="anthropic.claude-3-5-sonnet",
        )

        is_hit, response, similarity = self.cache.get("What is AWS VPC?", self.v1)
        self.assertTrue(is_hit)
        self.assertIsNotNone(response)
        self.assertTrue(response.cached)
        self.assertEqual(response.answer, "AWS VPC is a Virtual Private Cloud.")
        self.assertEqual(similarity, 1.0)
        self.assertEqual(len(response.citations), 1)

    def test_semantic_vector_cache_hit(self):
        citations = []
        self.cache.set(
            query="How does Amazon S3 encryption work?",
            query_embedding=self.v1,
            answer="S3 supports SSE-KMS with customer-managed keys.",
            citations=citations,
            model_id="anthropic.claude-3-5-sonnet",
        )

        # Query with slightly different phrasing and similar embedding vector
        is_hit, response, similarity = self.cache.get(
            query="Explain S3 bucket encryption with KMS keys",
            query_embedding=self.v1_similar,
            threshold=0.90,
        )
        self.assertTrue(is_hit)
        self.assertIsNotNone(response)
        self.assertTrue(response.cached)
        self.assertGreaterEqual(similarity, 0.90)

    def test_semantic_cache_miss_below_threshold(self):
        self.cache.set(
            query="How does Aurora PostgreSQL pgvector work?",
            query_embedding=self.v1,
            answer="pgvector enables vector storage and HNSW indexing.",
            citations=[],
            model_id="anthropic.claude-3-5-sonnet",
        )

        # Completely unrelated query
        is_hit, response, similarity = self.cache.get(
            query="What is the weather in Seattle?",
            query_embedding=self.v_different,
            threshold=0.90,
        )
        self.assertFalse(is_hit)
        self.assertIsNone(response)
        self.assertLess(similarity, 0.90)


if __name__ == "__main__":
    unittest.main()
