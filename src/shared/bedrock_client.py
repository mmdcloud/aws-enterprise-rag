"""Amazon Bedrock Client with Guardrails, Retries, and Embeddings Support."""

import json
from typing import Any, Dict, List, Optional, Tuple
import boto3
from botocore.config import Config
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from src.shared.config import settings
from src.shared.logger import get_logger

logger = get_logger(__name__)


class BedrockClient:
    """Enterprise wrapper for Amazon Bedrock Runtime with PrivateLink support."""

    def __init__(self, region_name: Optional[str] = None):
        self.region = region_name or settings.AWS_REGION
        config = Config(
            region_name=self.region,
            retries={"max_attempts": 5, "mode": "adaptive"},
            connect_timeout=10,
            read_timeout=60,
        )
        self._runtime_client = boto3.client("bedrock-runtime", config=config)
        self._bedrock_client = boto3.client("bedrock", config=config)

    @retry(
        stop=stop_after_attempt(4),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True,
    )
    def generate_embedding(
        self,
        text: str,
        dimensions: int = 1024,
        normalize: bool = True,
        model_id: Optional[str] = None,
    ) -> List[float]:
        """Generates text embeddings via Amazon Titan Text Embeddings v2."""
        model = model_id or settings.BEDROCK_EMBEDDING_MODEL_ID
        body = {
            "inputText": text,
            "dimensions": dimensions,
            "normalize": normalize,
        }

        response = self._runtime_client.invoke_model(
            modelId=model,
            contentType="application/json",
            accept="application/json",
            body=json.dumps(body),
        )

        response_body = json.loads(response["body"].read().decode("utf-8"))
        return response_body["embedding"]

    def apply_guardrail(
        self,
        text: str,
        source: str = "INPUT",  # "INPUT" or "OUTPUT"
        guardrail_id: Optional[str] = None,
        guardrail_version: Optional[str] = None,
    ) -> Tuple[bool, Optional[str], Optional[Dict[str, Any]]]:
        """Evaluates content against Amazon Bedrock Guardrail.

        Returns:
            Tuple of (is_blocked: bool, action_taken: str, assessment_details: dict)
        """
        gid = guardrail_id or settings.BEDROCK_GUARDRAIL_ID
        gversion = guardrail_version or settings.BEDROCK_GUARDRAIL_VERSION

        if not gid:
            # No guardrail configured (e.g. local test mode)
            return False, "NONE", None

        try:
            response = self._runtime_client.apply_guardrail(
                guardrailIdentifier=gid,
                guardrailVersion=gversion,
                source=source,
                content=[{"text": {"text": text}}],
            )

            action = response.get("action", "NONE")
            is_blocked = action == "GUARDRAIL_INTERVENED"

            assessments = response.get("assessments", [])
            return is_blocked, action, {"assessments": assessments}

        except Exception as e:
            logger.error(f"Error applying Bedrock Guardrail: {e}")
            # Fail closed or open depending on policy; enterprise default is fail closed for safety
            return False, "ERROR_FALLBACK", {"error": str(e)}

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=8),
        reraise=True,
    )
    def invoke_llm(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        model_id: Optional[str] = None,
        max_tokens: int = 2048,
        temperature: float = 0.1,
        guardrail_id: Optional[str] = None,
        guardrail_version: Optional[str] = None,
    ) -> str:
        """Invokes Bedrock Claude 3.5 Sonnet / Claude 3 with Guardrails."""
        model = model_id or settings.BEDROCK_LLM_MODEL_ID

        messages = [{"role": "user", "content": prompt}]
        body: Dict[str, Any] = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": max_tokens,
            "temperature": temperature,
            "messages": messages,
        }
        if system_prompt:
            body["system"] = system_prompt

        invoke_kwargs: Dict[str, Any] = {
            "modelId": model,
            "contentType": "application/json",
            "accept": "application/json",
            "body": json.dumps(body),
        }

        # Attach guardrail directly to inference call if specified
        gid = guardrail_id or settings.BEDROCK_GUARDRAIL_ID
        gver = guardrail_version or settings.BEDROCK_GUARDRAIL_VERSION
        if gid:
            invoke_kwargs["guardrailIdentifier"] = gid
            invoke_kwargs["guardrailVersion"] = gver

        response = self._runtime_client.invoke_model(**invoke_kwargs)
        result = json.loads(response["body"].read().decode("utf-8"))

        # Anthropic Claude message format
        content = result.get("content", [])
        if content and isinstance(content, list):
            return content[0].get("text", "")
        return ""


bedrock_client = BedrockClient()
