"""Enterprise RAG Query Pipeline Orchestrator."""

import time
from typing import Optional
from src.query.generator import generator
from src.query.retriever import retriever
from src.query.semantic_cache import semantic_cache
from src.shared.bedrock_client import bedrock_client
from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.metrics import metrics
from src.shared.models import QueryRequest, QueryResponse

logger = get_logger(__name__)


class EnterpriseRAGEngine:
    """Production End-to-End RAG Query Engine:

    1. Bedrock Guardrail Evaluation (Prompt Injection & Topic Defense)
    2. Titan v2 Query Embedding Generation
    3. Redis Semantic Cache Vector Cosine Similarity Check (O(1) / <15ms HIT)
    4. Aurora pgvector Retrieval with HNSW cosine search (<=>)
    5. Bedrock Claude 3.5 Sonnet / Claude 3 Grounded Generation
    6. Asynchronous Semantic Cache Insertion with TTL
    7. CloudWatch Custom Metric Publication
    """

    def __init__(
        self,
        cache=None,
        vector_retriever=None,
        llm_generator=None,
    ):
        self.cache = cache or semantic_cache
        self.retriever = vector_retriever or retriever
        self.generator = llm_generator or generator

    def execute_query(self, request: QueryRequest) -> QueryResponse:
        total_start = time.time()
        logger.info(f"Processing query: '{request.query}' (top_k={request.top_k})")

        # 1. Security & Governance: Bedrock Guardrail check on User Input
        is_blocked, action, assessment = bedrock_client.apply_guardrail(
            text=request.query,
            source="INPUT",
        )
        if is_blocked:
            metrics.record_guardrail_block("Input")
            logger.warning(f"Guardrail INTERVENED for input query: {assessment}")
            return QueryResponse(
                answer="I am unable to process this request because it violated enterprise security and safety policies.",
                cached=False,
                citations=[],
                latency_ms=(time.time() - total_start) * 1000,
                cache_lookup_latency_ms=0.0,
                model_id=settings.BEDROCK_LLM_MODEL_ID,
                guardrail_applied=True,
                guardrail_action=action,
            )

        # 2. Embedding Generation for User Query
        emb_start = time.time()
        query_embedding = bedrock_client.generate_embedding(
            text=request.query,
            dimensions=settings.EMBEDDING_DIMENSION,
            normalize=True,
        )
        emb_latency = (time.time() - emb_start) * 1000
        metrics.record_latency("QueryEmbeddingLatencyMs", emb_latency)

        # 3. Check Redis Semantic Cache
        cache_start = time.time()
        threshold = request.similarity_threshold or settings.SEMANTIC_CACHE_SIMILARITY_THRESHOLD
        is_hit, cached_response, similarity = self.cache.get(
            query=request.query,
            query_embedding=query_embedding,
            threshold=threshold,
        )
        cache_lookup_latency = (time.time() - cache_start) * 1000
        metrics.record_latency("CacheLookupLatencyMs", cache_lookup_latency)

        if is_hit and cached_response:
            metrics.record_cache_hit()
            total_latency = (time.time() - total_start) * 1000
            metrics.record_latency("QueryLatencyMs", total_latency)
            cached_response.latency_ms = round(total_latency, 2)
            cached_response.cache_lookup_latency_ms = round(cache_lookup_latency, 2)
            return cached_response

        # Cache MISS
        metrics.record_cache_miss()

        # 4. Storage & Retrieval: Aurora PostgreSQL pgvector Search
        retrieval_start = time.time()
        citations = self.retriever.retrieve(
            query_embedding=query_embedding,
            top_k=request.top_k,
            filter_metadata=request.filter,
        )
        retrieval_latency = (time.time() - retrieval_start) * 1000
        metrics.record_latency("VectorSearchLatencyMs", retrieval_latency)

        if not citations:
            total_latency = (time.time() - total_start) * 1000
            return QueryResponse(
                answer="No relevant documents were found in the enterprise knowledge base to answer your question.",
                cached=False,
                citations=[],
                latency_ms=round(total_latency, 2),
                cache_lookup_latency_ms=round(cache_lookup_latency, 2),
                generation_latency_ms=0.0,
                model_id=settings.BEDROCK_LLM_MODEL_ID,
            )

        # 5. LLM Response Generation via Bedrock
        answer, gen_latency = self.generator.generate_response(
            query=request.query,
            citations=citations,
        )
        metrics.record_latency("LLMGenerationLatencyMs", gen_latency)

        # 6. Post-generation Guardrail Check on Generated Output
        out_blocked, out_action, out_assessment = bedrock_client.apply_guardrail(
            text=answer,
            source="OUTPUT",
        )
        if out_blocked:
            metrics.record_guardrail_block("Output")
            logger.warning(f"Guardrail INTERVENED for generated output: {out_assessment}")
            answer = "The generated response was withheld in accordance with enterprise data protection guidelines."

        # 7. Write to Semantic Cache for Subsequent Repeated / Paraphrased Queries
        if not out_blocked and answer:
            self.cache.set(
                query=request.query,
                query_embedding=query_embedding,
                answer=answer,
                citations=citations,
                model_id=settings.BEDROCK_LLM_MODEL_ID,
            )

        total_latency = (time.time() - total_start) * 1000
        metrics.record_latency("QueryLatencyMs", total_latency)

        return QueryResponse(
            answer=answer,
            cached=False,
            similarity_score=round(similarity, 4) if similarity > 0 else None,
            citations=citations,
            latency_ms=round(total_latency, 2),
            cache_lookup_latency_ms=round(cache_lookup_latency, 2),
            generation_latency_ms=round(gen_latency, 2),
            model_id=settings.BEDROCK_LLM_MODEL_ID,
            guardrail_applied=out_blocked,
            guardrail_action=out_action if out_blocked else None,
        )


rag_engine = EnterpriseRAGEngine()
