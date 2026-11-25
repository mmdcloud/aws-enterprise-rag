"""Unit tests for Aurora pgvector Retriever."""

import unittest
from unittest.mock import MagicMock
from src.query.retriever import PgvectorRetriever


class TestPgvectorRetriever(unittest.TestCase):

    def setUp(self):
        self.mock_store = MagicMock()
        self.retriever = PgvectorRetriever(store=self.mock_store)

    def test_retrieve_chunks_success(self):
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        self.mock_store._get_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        # Mock DB rows returned: doc_id, chunk_id, source_uri, chunk_index, chunk_text, meta, score
        mock_cursor.fetchall.return_value = [
            (
                "doc-101",
                "chunk-1",
                "s3://ent-rag-docs/policy.pdf",
                0,
                "Enterprise security requires encryption at rest and in transit.",
                {"department": "compliance"},
                0.9421,
            ),
            (
                "doc-101",
                "chunk-2",
                "s3://ent-rag-docs/policy.pdf",
                1,
                "All vector endpoints must use AWS PrivateLink VPC interface endpoints.",
                {"department": "infrastructure"},
                0.8912,
            ),
        ]

        dummy_embedding = [0.1] * 1024
        citations = self.retriever.retrieve(
            query_embedding=dummy_embedding,
            top_k=2,
            filter_metadata={"department": "compliance"},
        )

        self.assertEqual(len(citations), 2)
        self.assertEqual(citations[0].document_id, "doc-101")
        self.assertEqual(citations[0].chunk_id, "chunk-1")
        self.assertEqual(citations[0].score, 0.9421)
        self.assertIn("Enterprise security", citations[0].text_snippet)
        mock_cursor.close.assert_called_once()
        mock_conn.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
