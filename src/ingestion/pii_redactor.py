"""PII Detection and Redaction using Amazon Comprehend with Regex Fallback."""

import re
from typing import List, Set, Tuple
import boto3
from botocore.config import Config

from src.shared.config import settings
from src.shared.logger import get_logger

logger = get_logger(__name__)

# Enterprise PII regex fallback patterns
PII_PATTERNS = {
    "SSN": re.compile(r"\b\d{3}-\d{2}-\d{4}\b"),
    "CREDIT_CARD": re.compile(r"\b(?:\d[ -]*?){13,16}\b"),
    "EMAIL": re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"),
    "PHONE": re.compile(r"\b(?:\+?1[-.\s]?)?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"),
    "AWS_KEY": re.compile(r"\b(AKIA|ABIA|ACCA|ASIA)[A-Z0-9]{16}\b"),
}


class PIIRedactor:
    """Enterprise PII Redaction leveraging Amazon Comprehend and regex rules."""

    def __init__(self, comprehend_client=None):
        self._client = comprehend_client

    @property
    def client(self):
        if self._client is None:
            config = Config(region_name=settings.AWS_REGION, retries={"max_attempts": 3})
            self._client = boto3.client("comprehend", config=config)
        return self._client

    def redact_pii(self, text: str, language_code: str = "en") -> Tuple[str, List[str]]:
        """Detects and redacts PII entities from text.

        Returns:
            Tuple of (redacted_text, list_of_detected_entity_types)
        """
        detected_types: Set[str] = set()
        redacted = text

        # 1. Regex-based primary redaction for high-risk structured tokens
        for entity_type, pattern in PII_PATTERNS.items():
            matches = list(pattern.finditer(redacted))
            if matches:
                detected_types.add(entity_type)
                redacted = pattern.sub(f"[REDACTED_{entity_type}]", redacted)

        # 2. Amazon Comprehend PII detection for semantic contextual entities (Name, Address, etc.)
        # Comprehend batch limit is 100,000 bytes per request
        try:
            chunks_to_check = self._split_text_for_comprehend(redacted, max_bytes=80000)
            redacted_chunks = []

            for chunk in chunks_to_check:
                if not chunk.strip():
                    redacted_chunks.append(chunk)
                    continue

                response = self.client.detect_pii_entities(
                    Text=chunk,
                    LanguageCode=language_code,
                )

                entities = response.get("Entities", [])
                # Sort entities by BeginOffset descending so redaction doesn't displace subsequent offsets
                entities.sort(key=lambda x: x["BeginOffset"], reverse=True)

                chunk_chars = list(chunk)
                for ent in entities:
                    ent_type = ent["Type"]
                    score = ent.get("Score", 0.0)
                    if score >= 0.80:
                        detected_types.add(ent_type)
                        b = ent["BeginOffset"]
                        e = ent["EndOffset"]
                        chunk_chars[b:e] = list(f"[REDACTED_{ent_type}]")

                redacted_chunks.append("".join(chunk_chars))

            redacted = "".join(redacted_chunks)

        except Exception as e:
            logger.warning(f"Comprehend PII detection fallback to regex-only: {e}")

        logger.info(f"PII Redaction completed. Entities found: {list(detected_types)}")
        return redacted, sorted(list(detected_types))

    def _split_text_for_comprehend(self, text: str, max_bytes: int = 80000) -> List[str]:
        """Splits text into chunks under Comprehend's max byte limit along newline boundaries."""
        if len(text.encode("utf-8")) <= max_bytes:
            return [text]

        lines = text.splitlines(keepends=True)
        chunks = []
        current_chunk = []
        current_bytes = 0

        for line in lines:
            line_bytes = len(line.encode("utf-8"))
            if current_bytes + line_bytes > max_bytes and current_chunk:
                chunks.append("".join(current_chunk))
                current_chunk = [line]
                current_bytes = line_bytes
            else:
                current_chunk.append(line)
                current_bytes += line_bytes

        if current_chunk:
            chunks.append("".join(current_chunk))

        return chunks


pii_redactor = PIIRedactor()
