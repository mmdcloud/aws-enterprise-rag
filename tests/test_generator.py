"""Unit tests for LLM Generator with Bedrock."""

import unittest
from unittest.mock import patch
from src.query.generator import LLMGenerator
from src.shared.models import Citation


class TestLLMGenerator(unittest.TestCase):

    def setUp(self):
        self.generator = LLMGenerator(model_id="anthropic.claude-3-5-sonnet-20241022-v2:0")

    @patch("src.query.generator.bedrock_client.invoke_llm")
    def test_generate_response_success(self, mock_invoke):
        mock_invoke.return_value = (
            "Enterprise RAG achieves sub-15ms latency when hitting the Redis semantic cache."
        )

        citations = [
            Citation(
                document_id="doc-1",
                chunk_id="chunk-1",
                source_uri="s3://ent-rag-docs/arch.pdf",
                score=0.96,
                text_snippet="Semantic caching in Redis cuts LLM token costs and reduces query latency.",
                chunk_index=0,
            )
        ]

        answer, latency = self.generator.generate_response(
            query="What is the benefit of semantic caching?",
            citations=citations,
        )

        self.assertIn("sub-15ms latency", answer)
        self.assertGreater(latency, 0.0)
        mock_invoke.assert_called_once()


if __name__ == "__main__":
    unittest.main()
