"""Application Configuration using Pydantic Settings."""

import os
from typing import Optional
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Environment
    ENVIRONMENT: str = "prod"
    LOG_LEVEL: str = "INFO"
    AWS_REGION: str = "us-east-1"

    # Aurora Database
    AURORA_SECRET_ARN: Optional[str] = None
    AURORA_CLUSTER_ENDPOINT: Optional[str] = None
    DATABASE_NAME: str = "enterpriserag"
    DB_USER: str = "postgres"
    DB_PASSWORD: str = ""
    DB_PORT: int = 5432

    # ElastiCache Redis
    REDIS_ENDPOINT: str = "127.0.0.1"
    REDIS_PORT: int = 6379
    REDIS_USE_SSL: bool = True
    REDIS_PASSWORD: Optional[str] = None

    # Semantic Cache
    SEMANTIC_CACHE_TTL_SECONDS: int = 86400  # 24 hours
    SEMANTIC_CACHE_SIMILARITY_THRESHOLD: float = 0.92

    # Bedrock Models & Guardrails
    BEDROCK_EMBEDDING_MODEL_ID: str = "amazon.titan-embed-text-v2:0"
    BEDROCK_LLM_MODEL_ID: str = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    BEDROCK_GUARDRAIL_ID: Optional[str] = None
    BEDROCK_GUARDRAIL_VERSION: str = "1"

    # Chunking & Embeddings
    CHUNK_SIZE: int = 1000
    CHUNK_OVERLAP: int = 200
    EMBEDDING_DIMENSION: int = 1024

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
