"""Database Schema Initializer Lambda Handler."""

import os
from pathlib import Path
from typing import Any, Dict
from src.ingestion.vector_store import vector_store
from src.shared.logger import get_logger

logger = get_logger(__name__)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Applies schema migrations to Aurora PostgreSQL pgvector instance."""
    logger.info("Initializing Aurora PostgreSQL pgvector schema...")

    schema_file = Path(__file__).parent / "schema.sql"
    with open(schema_file, "r") as f:
        schema_sql = f.read()

    conn = vector_store._get_connection()
    try:
        cursor = conn.cursor()
        # Execute migration statements
        for statement in schema_sql.split(";"):
            stmt = statement.strip()
            if stmt:
                logger.info(f"Executing: {stmt[:60]}...")
                cursor.execute(stmt)

        conn.commit()
        cursor.close()
        logger.info("Database schema initialized and verified successfully.")
        return {"status": "SUCCESS", "message": "pgvector schema and HNSW indexes created."}
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to initialize database schema: {e}", exc_info=True)
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    lambda_handler({}, None)
