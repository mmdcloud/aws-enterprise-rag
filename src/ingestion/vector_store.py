"""Aurora PostgreSQL pgvector Storage Layer."""

import json
from typing import Any, Dict, List, Optional
import boto3

from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.models import DocumentChunk, DocumentMetadata

logger = get_logger(__name__)


class AuroraVectorStore:
    """Vector database layer for Aurora Serverless v2 PostgreSQL with pgvector."""

    def __init__(
        self,
        endpoint: Optional[str] = None,
        database: Optional[str] = None,
        secret_arn: Optional[str] = None,
    ):
        self.endpoint = endpoint or settings.AURORA_CLUSTER_ENDPOINT
        self.database = database or settings.DATABASE_NAME
        self.secret_arn = secret_arn or settings.AURORA_SECRET_ARN
        self._cached_credentials = None

    def _get_credentials(self) -> Dict[str, Any]:
        """Retrieves DB credentials from AWS Secrets Manager."""
        if self._cached_credentials:
            return self._cached_credentials

        if self.secret_arn:
            client = boto3.client("secretsmanager", region_name=settings.AWS_REGION)
            response = client.get_secret_value(SecretId=self.secret_arn)
            secret_data = json.loads(response["SecretString"])
            self._cached_credentials = secret_data
            return secret_data

        # Fallback to config settings (e.g. for local testing)
        return {
            "username": settings.DB_USER,
            "password": settings.DB_PASSWORD,
            "host": self.endpoint or "127.0.0.1",
            "port": settings.DB_PORT,
            "database": self.database,
        }

    def _get_connection(self):
        """Creates a PostgreSQL connection using pg8000 (pure Python) or psycopg2."""
        creds = self._get_credentials()
        host = creds.get("host", self.endpoint)
        user = creds.get("username", "postgres")
        password = creds.get("password", "")
        port = int(creds.get("port", 5432))
        dbname = creds.get("database", self.database)

        try:
            import pg8000.dbapi
            return pg8000.dbapi.connect(
                user=user,
                password=password,
                host=host,
                port=port,
                database=dbname,
                ssl_context=True if settings.ENVIRONMENT != "local" else None,
            )
        except ImportError:
            try:
                import psycopg2
                return psycopg2.connect(
                    user=user,
                    password=password,
                    host=host,
                    port=port,
                    dbname=dbname,
                )
            except ImportError:
                raise RuntimeError("Neither pg8000 nor psycopg2 is available in environment")

    def store_document_and_chunks(
        self,
        document_id: str,
        source_uri: str,
        chunks: List[DocumentChunk],
        metadata: Optional[Dict[str, Any]] = None,
    ) -> int:
        """Atomically inserts or updates document record and its vector chunks."""
        meta = metadata or {}
        conn = self._get_connection()
        try:
            cursor = conn.cursor()

            # 1. Upsert document record
            cursor.execute(
                """
                INSERT INTO documents (document_id, source_uri, total_chunks, metadata)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (document_id) DO UPDATE SET
                    total_chunks = EXCLUDED.total_chunks,
                    metadata = EXCLUDED.metadata,
                    updated_at = CURRENT_TIMESTAMP;
                """,
                (document_id, source_uri, len(chunks), json.dumps(meta)),
            )

            # 2. Delete old chunks for idempotency on re-ingestion
            cursor.execute(
                "DELETE FROM document_chunks WHERE document_id = %s;",
                (document_id,),
            )

            # 3. Batch insert chunk vectors
            for chunk in chunks:
                if not chunk.embedding:
                    continue

                vector_str = "[" + ",".join(str(f) for f in chunk.embedding) + "]"
                cursor.execute(
                    """
                    INSERT INTO document_chunks (
                        chunk_id, document_id, chunk_index, chunk_text,
                        token_count, metadata, embedding
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s::vector);
                    """,
                    (
                        chunk.chunk_id,
                        chunk.document_id,
                        chunk.chunk_index,
                        chunk.text,
                        chunk.token_count,
                        json.dumps(chunk.metadata),
                        vector_str,
                    ),
                )

            conn.commit()
            cursor.close()
            logger.info(f"Successfully upserted {len(chunks)} chunks for doc {document_id}")
            return len(chunks)

        except Exception as e:
            conn.rollback()
            logger.error(f"Failed to upsert chunks to Aurora pgvector: {e}")
            raise
        finally:
            conn.close()


vector_store = AuroraVectorStore()
