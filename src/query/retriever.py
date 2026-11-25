"""Aurora PostgreSQL pgvector Retrieval Engine."""

import json
import time
from typing import Any, Dict, List, Optional
from src.ingestion.vector_store import vector_store
from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.models import Citation

logger = get_logger(__name__)


class PgvectorRetriever:
    """Performs cosine vector similarity search on Aurora PostgreSQL pgvector."""

    def __init__(self, store=None):
        self.store = store or vector_store

    def retrieve(
        self,
        query_embedding: List[float],
        top_k: int = 5,
        filter_metadata: Optional[Dict[str, Any]] = None,
    ) -> List[Citation]:
        """Retrieves top_k most similar document chunks using cosine distance (<=>).

        Returns:
            List of Citations ordered by cosine similarity descending.
        """
        start_time = time.time()
        conn = self.store._get_connection()
        try:
            cursor = conn.cursor()
            vector_str = "[" + ",".join(str(f) for f in query_embedding) + "]"

            # Build query with optional metadata filter
            where_clauses = ["1=1"]
            params: List[Any] = [vector_str]

            if filter_metadata:
                for k, v in filter_metadata.items():
                    where_clauses.append("c.metadata->>%s = %s")
                    params.extend([str(k), str(v)])

            where_sql = " AND ".join(where_clauses)
            params.extend([vector_str, top_k])

            query = f"""
                SELECT
                    c.document_id,
                    c.chunk_id,
                    d.source_uri,
                    c.chunk_index,
                    c.chunk_text,
                    c.metadata,
                    1 - (c.embedding <=> %s::vector) AS similarity_score
                FROM document_chunks c
                JOIN documents d ON c.document_id = d.document_id
                WHERE {where_sql}
                ORDER BY c.embedding <=> %s::vector ASC
                LIMIT %s;
            """

            cursor.execute(query, tuple(params))
            rows = cursor.fetchall()
            cursor.close()

            citations: List[Citation] = []
            for row in rows:
                doc_id, chunk_id, source_uri, chunk_index, chunk_text, meta, score = row
                citations.append(
                    Citation(
                        document_id=str(doc_id),
                        chunk_id=str(chunk_id),
                        source_uri=str(source_uri),
                        score=round(float(score), 4),
                        text_snippet=str(chunk_text),
                        chunk_index=int(chunk_index),
                    )
                )

            latency = (time.time() - start_time) * 1000
            logger.info(f"Retrieved {len(citations)} chunks from pgvector in {latency:.2f}ms")
            return citations

        except Exception as e:
            logger.error(f"Error querying Aurora pgvector: {e}")
            raise
        finally:
            conn.close()


retriever = PgvectorRetriever()
