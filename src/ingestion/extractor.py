"""Document Text Extractor supporting PDF, Markdown, Text, and JSON from S3."""

import io
import json
import uuid
from typing import Any, Dict, Tuple
import boto3
from pypdf import PdfReader

from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.models import DocumentMetadata

logger = get_logger(__name__)


class DocumentExtractor:
    """Extracts raw text and metadata from files stored in Amazon S3."""

    def __init__(self, s3_client=None):
        self._s3_client = s3_client

    @property
    def s3(self):
        if self._s3_client is None:
            self._s3_client = boto3.client("s3", region_name=settings.AWS_REGION)
        return self._s3_client

    def extract_from_s3(self, bucket: str, key: str) -> Tuple[str, str, DocumentMetadata]:
        """Fetches document from S3 and extracts clean text and metadata.

        Returns:
            Tuple of (document_id, extracted_text, metadata)
        """
        logger.info(f"Extracting document from s3://{bucket}/{key}")
        response = self.s3.get_object(Bucket=bucket, Key=key)
        content_type = response.get("ContentType", "application/octet-stream")
        content_length = response.get("ContentLength", 0)
        file_bytes = response["Body"].read()

        doc_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"s3://{bucket}/{key}"))
        extracted_text, page_count = self._parse_bytes(file_bytes, key, content_type)

        metadata = DocumentMetadata(
            source_uri=f"s3://{bucket}/{key}",
            content_type=content_type,
            file_size_bytes=content_length,
            page_count=page_count,
            title=key.split("/")[-1],
            custom_metadata={"bucket": bucket, "key": key},
        )

        logger.info(f"Extracted {len(extracted_text)} chars from {key} (doc_id: {doc_id})")
        return doc_id, extracted_text, metadata

    def _parse_bytes(self, file_bytes: bytes, filename: str, content_type: str) -> Tuple[str, int]:
        """Parses byte payload according to format."""
        lower_fn = filename.lower()

        # PDF parsing
        if lower_fn.endswith(".pdf") or "pdf" in content_type:
            try:
                reader = PdfReader(io.BytesIO(file_bytes))
                pages_text = []
                for idx, page in enumerate(reader.pages):
                    text = page.extract_text() or ""
                    pages_text.append(f"--- Page {idx + 1} ---\n{text}")
                return "\n\n".join(pages_text).strip(), len(reader.pages)
            except Exception as e:
                logger.error(f"PDF extraction error for {filename}: {e}")
                raise

        # JSON parsing
        if lower_fn.endswith(".json") or "json" in content_type:
            try:
                data = json.loads(file_bytes.decode("utf-8"))
                return json.dumps(data, indent=2), 1
            except Exception:
                pass

        # Text / Markdown fallback
        text = file_bytes.decode("utf-8", errors="replace")
        return text.strip(), 1


document_extractor = DocumentExtractor()
