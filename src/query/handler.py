"""AWS Lambda API Gateway Entrypoint for Enterprise RAG Query Service."""

import json
from typing import Any, Dict
from pydantic import ValidationError

from src.query.rag_engine import rag_engine
from src.query.semantic_cache import semantic_cache
from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.models import QueryRequest

logger = get_logger(__name__)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Handles API Gateway HTTP API v2 requests."""
    logger.info(f"API Request: {event.get('routeKey')} {event.get('rawPath')}")

    # Determine route and method
    route_key = event.get("routeKey", "")
    raw_path = event.get("rawPath", "")
    http_method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Api-Key",
    }

    # Handle CORS preflight
    if http_method == "OPTIONS":
        return {"statusCode": 200, "headers": headers, "body": ""}

    # 1. GET /health
    if "GET /health" in route_key or raw_path.endswith("/health"):
        return {
            "statusCode": 200,
            "headers": headers,
            "body": json.dumps(
                {
                    "status": "UP",
                    "version": "1.0.0",
                    "environment": settings.ENVIRONMENT,
                    "service": "aws-enterprise-rag",
                    "bedrock_embedding_model": settings.BEDROCK_EMBEDDING_MODEL_ID,
                    "bedrock_llm_model": settings.BEDROCK_LLM_MODEL_ID,
                }
            ),
        }

    # 2. GET /metrics (Cache & System Status)
    if "GET /metrics" in route_key or raw_path.endswith("/metrics"):
        try:
            cached_query_ids = semantic_cache.client.smembers(semantic_cache.SEMANTIC_SET)
            active_cache_count = len(cached_query_ids)
        except Exception:
            active_cache_count = -1

        return {
            "statusCode": 200,
            "headers": headers,
            "body": json.dumps(
                {
                    "active_semantic_cache_entries": active_cache_count,
                    "similarity_threshold": settings.SEMANTIC_CACHE_SIMILARITY_THRESHOLD,
                    "cache_ttl_seconds": settings.SEMANTIC_CACHE_TTL_SECONDS,
                }
            ),
        }

    # 3. POST /query (Vector search + Semantic Cache + Bedrock Generation)
    if "POST /query" in route_key or raw_path.endswith("/query") or http_method == "POST":
        try:
            body_str = event.get("body", "{}")
            if event.get("isBase64Encoded", False):
                import base64
                body_str = base64.b64decode(body_str).decode("utf-8")

            body_dict = json.loads(body_str) if body_str else {}
            request_obj = QueryRequest(**body_dict)

            response = rag_engine.execute_query(request_obj)
            return {
                "statusCode": 200,
                "headers": headers,
                "body": response.model_dump_json(),
            }

        except ValidationError as ve:
            logger.warning(f"Request validation error: {ve}")
            return {
                "statusCode": 400,
                "headers": headers,
                "body": json.dumps({"error": "Bad Request", "details": ve.errors()}),
            }
        except Exception as e:
            logger.error(f"Internal query processing error: {e}", exc_info=True)
            return {
                "statusCode": 500,
                "headers": headers,
                "body": json.dumps(
                    {
                        "error": "Internal Server Error",
                        "message": "An unexpected error occurred while executing the RAG query.",
                    }
                ),
            }

    return {
        "statusCode": 404,
        "headers": headers,
        "body": json.dumps({"error": "Not Found", "route": route_key or raw_path}),
    }
