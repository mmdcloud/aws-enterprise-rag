"""Structured JSON Logging for AWS Enterprise RAG."""

import json
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Dict, Optional


class JSONFormatter(logging.Formatter):
    """Custom formatter emitting structured single-line JSON logs."""

    def format(self, record: logging.LogRecord) -> str:
        log_entry: Dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }

        # Add custom extra fields
        if hasattr(record, "extra") and isinstance(record.extra, dict):
            log_entry.update(record.extra)

        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_entry)


def get_logger(name: str, level: Optional[str] = None) -> logging.Logger:
    """Creates a configured structured JSON logger."""
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JSONFormatter())
        logger.addHandler(handler)
        log_lvl = level or os.getenv("LOG_LEVEL", "INFO")
        logger.setLevel(getattr(logging, log_lvl.upper(), logging.INFO))
        logger.propagate = False
    return logger
