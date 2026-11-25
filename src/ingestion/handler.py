"""Step Functions Task Dispatcher / Ingestion Lambda Handler."""

import json
from typing import Any, Dict
from src.ingestion.chunker import chunker
from src.ingestion.embedder import embedder
from src.ingestion.extractor import document_extractor
from src.ingestion.pii_redactor import pii_redactor
from src.ingestion.vector_store import vector_store
from src.shared.logger import get_logger
from src.shared.models import DocumentChunk

logger = get_logger(__name__)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Dispatches execution for each Step Functions ingestion pipeline step."""
    logger.info(f"Received ingestion event: {json.dumps(event)}")
    action = event.get("action")

    try:
        # Step 1: Extract Document from S3
        if action == "extract":
            bucket = event["bucket"]
            key = event["key"]
            doc_id, raw_text, metadata = document_extractor.extract_from_s3(bucket, key)
            return {
                "document_id": doc_id,
                "raw_text": raw_text,
                "metadata": metadata.model_dump(mode="json"),
                "source_s3_uri": f"s3://{bucket}/{key}",
            }

        # Step 2: Redact PII
        elif action == "redact_pii":
            text = event["text"]
            redacted_text, detected_entities = pii_redactor.redact_pii(text)
            return {
                "redacted_text": redacted_text,
                "pii_entities_detected": detected_entities,
            }

        # Step 3: Semantic Chunking
        elif action == "chunk":
            document_id = event["document_id"]
            text = event["text"]
            metadata = event.get("metadata", {})
            chunks = chunker.chunk_document(document_id, text, metadata)
            return {
                "chunks": [c.model_dump(mode="json") for c in chunks],
                "total_chunks": len(chunks),
            }

        # Step 4: Generate Bedrock Titan Embeddings v2
        elif action == "generate_embeddings":
            document_id = event["document_id"]
            raw_chunks = event["chunks"]
            chunks_obj = [DocumentChunk(**c) for c in raw_chunks]
            embedded_chunks = embedder.embed_chunks(chunks_obj)
            return {
                "embedded_chunks": [c.model_dump(mode="json") for c in embedded_chunks],
                "model_id": embedder.model_id,
            }

        # Step 5: Store Vectors in Aurora PostgreSQL pgvector
        elif action == "store_vectors":
            document_id = event["document_id"]
            source_s3_uri = event.get("source_s3_uri", "")
            raw_chunks = event["embedded_chunks"]
            metadata = event.get("metadata", {})
            chunks_obj = [DocumentChunk(**c) for c in raw_chunks]
            stored_count = vector_store.store_document_and_chunks(
                document_id=document_id,
                source_uri=source_s3_uri,
                chunks=chunks_obj,
                metadata=metadata,
            )
            return {
                "status": "COMPLETED",
                "chunks_indexed": stored_count,
                "document_id": document_id,
            }

        else:
            raise ValueError(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"Error executing action '{action}': {e}", exc_info=True)
        raise
