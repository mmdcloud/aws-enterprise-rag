"""Embedder module leveraging Amazon Bedrock Titan Text Embeddings v2."""

import time
from typing import List, Optional
from src.shared.bedrock_client import bedrock_client
from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.models import DocumentChunk

logger = get_logger(__name__)


class DocumentEmbedder:
    """Generates embeddings for chunks using Bedrock Titan Text Embeddings v2."""

    def __init__(
        self,
        model_id: Optional[str] = None,
        dimension: Optional[int] = None,
    ):
        self.model_id = model_id or settings.BEDROCK_EMBEDDING_MODEL_ID
        self.dimension = dimension or settings.EMBEDDING_DIMENSION

    def embed_chunks(self, chunks: List[DocumentChunk]) -> List[DocumentChunk]:
        """Embeds a batch of chunks sequentially with rate-limit respect."""
        start_time = time.time()
        logger.info(f"Generating embeddings for {len(chunks)} chunks with {self.model_id}")

        for idx, chunk in enumerate(chunks):
            try:
                embedding = bedrock_client.generate_embedding(
                    text=chunk.text,
                    dimensions=self.dimension,
                    normalize=True,
                    model_id=self.model_id,
                )
                chunk.embedding = embedding
            except Exception as e:
                logger.error(f"Failed to embed chunk {chunk.chunk_id} (index {idx}): {e}")
                raise

        duration = time.time() - start_time
        logger.info(f"Successfully generated {len(chunks)} embeddings in {duration:.2f}s")
        return chunks


embedder = DocumentEmbedder()
