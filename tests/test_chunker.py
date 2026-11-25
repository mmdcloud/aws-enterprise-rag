"""Unit tests for Semantic and Structural Document Chunker."""

import unittest
from src.ingestion.chunker import SemanticChunker


class TestSemanticChunker(unittest.TestCase):

    def setUp(self):
        self.chunker = SemanticChunker(chunk_size=100, chunk_overlap=20)

    def test_chunk_empty_text(self):
        chunks = self.chunker.chunk_document("doc-1", "")
        self.assertEqual(len(chunks), 0)

    def test_chunk_short_text(self):
        text = "This is a brief enterprise report about cloud infrastructure security."
        chunks = self.chunker.chunk_document("doc-1", text, {"category": "security"})
        self.assertEqual(len(chunks), 1)
        self.assertEqual(chunks[0].document_id, "doc-1")
        self.assertEqual(chunks[0].chunk_index, 0)
        self.assertEqual(chunks[0].text, text)
        self.assertEqual(chunks[0].metadata["category"], "security")
        self.assertGreater(chunks[0].token_count, 0)

    def test_chunk_multi_paragraph_with_overlap(self):
        p1 = "Paragraph 1: In modern enterprise software, security is paramount. Zero-trust networks prevent lateral movement."
        p2 = "Paragraph 2: Data in transit must always be encrypted with TLS 1.3 or higher. VPC endpoints enforce PrivateLink isolation."
        p3 = "Paragraph 3: Sensitive vectors are stored in Aurora PostgreSQL with the pgvector extension and HNSW cosine distance."
        text = f"{p1}\n\n{p2}\n\n{p3}"

        chunks = self.chunker.chunk_document("doc-2", text)
        self.assertGreaterEqual(len(chunks), 1)
        # Verify chunk indexes are sequential
        for idx, chunk in enumerate(chunks):
            self.assertEqual(chunk.chunk_index, idx)
            self.assertEqual(chunk.document_id, "doc-2")

    def test_chunk_long_sentence_splitting(self):
        long_sentence = "Data protection is crucial. " * 50
        chunks = self.chunker.chunk_document("doc-3", long_sentence)
        self.assertGreater(len(chunks), 1)


if __name__ == "__main__":
    unittest.main()
