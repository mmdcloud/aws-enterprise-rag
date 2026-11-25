"""Semantic and Structural Document Chunker."""

import re
import uuid
from typing import Any, Dict, List, Optional, Tuple
import tiktoken

from src.shared.config import settings
from src.shared.logger import get_logger
from src.shared.models import DocumentChunk

logger = get_logger(__name__)


class SemanticChunker:
    """Splits documents into overlapping semantic chunks with token counts and metadata."""

    def __init__(
        self,
        chunk_size: Optional[int] = None,
        chunk_overlap: Optional[int] = None,
    ):
        self.chunk_size = chunk_size or settings.CHUNK_SIZE
        self.chunk_overlap = chunk_overlap or settings.CHUNK_OVERLAP
        try:
            self._tokenizer = tiktoken.get_encoding("cl100k_base")
        except Exception:
            self._tokenizer = None

    def count_tokens(self, text: str) -> int:
        """Counts tokens using cl100k_base or character approximation fallback."""
        if self._tokenizer:
            return len(self._tokenizer.encode(text, disallowed_special=()))
        return max(1, len(text) // 4)

    def chunk_document(
        self,
        document_id: str,
        text: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> List[DocumentChunk]:
        """Performs recursive structural and semantic chunking.

        Breaks on paragraphs and sentences before cutting mid-sentence.
        """
        meta = metadata or {}
        if not text.strip():
            return []

        # Split into structural blocks (paragraphs, markdown headers)
        paragraphs = re.split(r"\n{2,}", text)
        chunks: List[DocumentChunk] = []

        current_text_segments: List[str] = []
        current_tokens = 0
        chunk_idx = 0

        for para in paragraphs:
            para_clean = para.strip()
            if not para_clean:
                continue

            para_tokens = self.count_tokens(para_clean)

            # If a single paragraph exceeds chunk_size, split by sentences
            if para_tokens > self.chunk_size:
                sentences = re.split(r"(?<=[.!?])\s+", para_clean)
                for sentence in sentences:
                    sentence_clean = sentence.strip()
                    if not sentence_clean:
                        continue
                    sent_tokens = self.count_tokens(sentence_clean)

                    if current_tokens + sent_tokens > self.chunk_size and current_text_segments:
                        chunk_text = " ".join(current_text_segments).strip()
                        chunks.append(self._create_chunk(document_id, chunk_idx, chunk_text, meta))
                        chunk_idx += 1

                        # Keep overlap
                        current_text_segments, current_tokens = self._extract_overlap(
                            current_text_segments
                        )

                    current_text_segments.append(sentence_clean)
                    current_tokens += sent_tokens
            else:
                if current_tokens + para_tokens > self.chunk_size and current_text_segments:
                    chunk_text = "\n\n".join(current_text_segments).strip()
                    chunks.append(self._create_chunk(document_id, chunk_idx, chunk_text, meta))
                    chunk_idx += 1

                    current_text_segments, current_tokens = self._extract_overlap(
                        current_text_segments
                    )

                current_text_segments.append(para_clean)
                current_tokens += para_tokens

        # Flush final remaining segment
        if current_text_segments:
            chunk_text = "\n\n".join(current_text_segments).strip()
            if chunk_text:
                chunks.append(self._create_chunk(document_id, chunk_idx, chunk_text, meta))

        logger.info(f"Chunked document {document_id} into {len(chunks)} chunks")
        return chunks

    def _extract_overlap(self, segments: List[str]) -> Tuple[List[str], int]:
        """Extracts trailing segments to satisfy chunk_overlap."""
        overlap_segments = []
        tokens = 0
        for seg in reversed(segments):
            seg_tokens = self.count_tokens(seg)
            if tokens + seg_tokens <= self.chunk_overlap:
                overlap_segments.insert(0, seg)
                tokens += seg_tokens
            else:
                break
        return overlap_segments, tokens

    def _create_chunk(
        self,
        document_id: str,
        chunk_idx: int,
        text: str,
        metadata: Dict[str, Any],
    ) -> DocumentChunk:
        tokens = self.count_tokens(text)
        chunk_uuid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{document_id}-{chunk_idx}"))
        chunk_meta = dict(metadata)
        chunk_meta["chunk_index"] = chunk_idx

        return DocumentChunk(
            chunk_id=chunk_uuid,
            document_id=document_id,
            chunk_index=chunk_idx,
            text=text,
            token_count=tokens,
            char_count=len(text),
            metadata=chunk_meta,
        )


chunker = SemanticChunker()
