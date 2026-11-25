"""Unit tests for Ingestion Lambda handler / Step Functions dispatcher."""

import unittest
from unittest.mock import patch
from src.ingestion.handler import lambda_handler
from src.shared.models import DocumentChunk, DocumentMetadata


class TestIngestionHandler(unittest.TestCase):

    @patch("src.ingestion.handler.document_extractor.extract_from_s3")
    def test_extract_action(self, mock_extract):
        mock_meta = DocumentMetadata(
            source_uri="s3://bucket/doc.txt",
            content_type="text/plain",
            file_size_bytes=100,
            title="doc.txt",
        )
        mock_extract.return_value = ("doc-123", "Sample enterprise document text", mock_meta)

        event = {"action": "extract", "bucket": "bucket", "key": "doc.txt"}
        res = lambda_handler(event, None)

        self.assertEqual(res["document_id"], "doc-123")
        self.assertEqual(res["raw_text"], "Sample enterprise document text")
        self.assertEqual(res["source_s3_uri"], "s3://bucket/doc.txt")

    @patch("src.ingestion.handler.pii_redactor.redact_pii")
    def test_redact_pii_action(self, mock_redact):
        mock_redact.return_value = ("Redacted text with [REDACTED_SSN]", ["SSN"])

        event = {"action": "redact_pii", "text": "Sensitive 123-45-6789 text"}
        res = lambda_handler(event, None)

        self.assertEqual(res["redacted_text"], "Redacted text with [REDACTED_SSN]")
        self.assertEqual(res["pii_entities_detected"], ["SSN"])

    @patch("src.ingestion.handler.chunker.chunk_document")
    def test_chunk_action(self, mock_chunk):
        mock_chunk.return_value = [
            DocumentChunk(
                chunk_id="chunk-1",
                document_id="doc-1",
                chunk_index=0,
                text="Chunk text",
                token_count=10,
                char_count=10,
            )
        ]

        event = {"action": "chunk", "document_id": "doc-1", "text": "Full text"}
        res = lambda_handler(event, None)

        self.assertEqual(res["total_chunks"], 1)
        self.assertEqual(len(res["chunks"]), 1)

    def test_invalid_action_raises_value_error(self):
        with self.assertRaises(ValueError):
            lambda_handler({"action": "unknown_action"}, None)


if __name__ == "__main__":
    unittest.main()
