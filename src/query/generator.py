"""Enterprise LLM Generation Engine with Bedrock Guardrails."""

import time
from typing import List, Optional, Tuple
from src.shared.bedrock_client import bedrock_client
from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.models import Citation

logger = get_logger(__name__)

SYSTEM_PROMPT = """You are an Enterprise AI Knowledge Assistant.
Your mission is to provide accurate, strictly factual, and comprehensive answers based exclusively on the provided Reference Context.

Rules:
1. Ground your answer solely on the provided context chunks.
2. If the context does not contain enough information to answer the question, state: "I do not have sufficient information in the enterprise documents to answer this question."
3. Cite the relevant source documents and chunk indexes when making factual statements.
4. Do not hallucinate, speculate, or mention external knowledge outside the provided reference text.
5. Adhere strictly to enterprise compliance and data protection guidelines.
"""


class LLMGenerator:
    """Handles prompt construction and Bedrock LLM generation with Guardrail enforcement."""

    def __init__(self, model_id: Optional[str] = None):
        self.model_id = model_id or settings.BEDROCK_LLM_MODEL_ID

    def generate_response(
        self,
        query: str,
        citations: List[Citation],
        temperature: float = 0.1,
        max_tokens: int = 2048,
    ) -> Tuple[str, float]:
        """Constructs grounded prompt and invokes Bedrock LLM.

        Returns:
            Tuple of (answer_text, latency_ms)
        """
        start_time = time.time()

        # Format context blocks
        context_blocks = []
        for idx, cit in enumerate(citations):
            context_blocks.append(
                f"[Document Source: {cit.source_uri} | Chunk {cit.chunk_index} | Relevance Score: {cit.score:.2f}]\n"
                f"{cit.text_snippet}\n"
            )

        context_str = "\n".join(context_blocks)
        prompt = (
            f"Reference Context:\n{context_str}\n\n"
            f"User Question:\n{query}\n\n"
            f"Provide a clear, grounded response with inline source attributions where applicable:"
        )

        logger.info(f"Invoking Bedrock model {self.model_id} with {len(citations)} context chunks")
        answer = bedrock_client.invoke_llm(
            prompt=prompt,
            system_prompt=SYSTEM_PROMPT,
            model_id=self.model_id,
            max_tokens=max_tokens,
            temperature=temperature,
        )

        latency_ms = (time.time() - start_time) * 1000
        logger.info(f"LLM generation finished in {latency_ms:.2f}ms")
        return answer.strip(), latency_ms


generator = LLMGenerator()
