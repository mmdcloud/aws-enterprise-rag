"""CloudWatch Custom Metrics Emitter for Enterprise RAG."""

import boto3
from typing import Dict, Optional
from src.shared.config import settings
from src.shared.logger import get_logger

logger = get_logger(__name__)


class CloudWatchMetrics:
    """Emits high-resolution custom operational metrics to CloudWatch."""

    def __init__(self, namespace: str = "EnterpriseRAG"):
        self.namespace = namespace
        self._cw_client = None

    @property
    def client(self):
        if self._cw_client is None:
            self._cw_client = boto3.client("cloudwatch", region_name=settings.AWS_REGION)
        return self._cw_client

    def emit_metric(
        self,
        name: str,
        value: float,
        unit: str = "Count",
        dimensions: Optional[Dict[str, str]] = None,
    ) -> None:
        """Puts a single metric data point to CloudWatch."""
        dims = [{"Name": "Environment", "Value": settings.ENVIRONMENT}]
        if dimensions:
            dims.extend([{"Name": k, "Value": str(v)} for k, v in dimensions.items()])

        try:
            self.client.put_metric_data(
                Namespace=self.namespace,
                MetricData=[
                    {
                        "MetricName": name,
                        "Value": float(value),
                        "Unit": unit,
                        "Dimensions": dims,
                    }
                ],
            )
        except Exception as e:
            # Metrics failures should never break runtime query or ingestion execution
            logger.warning(f"Failed to emit metric {name}: {e}")

    def record_cache_hit(self) -> None:
        self.emit_metric("CacheHits", 1.0, "Count")

    def record_cache_miss(self) -> None:
        self.emit_metric("CacheMisses", 1.0, "Count")

    def record_latency(self, metric_name: str, latency_ms: float) -> None:
        self.emit_metric(metric_name, latency_ms, "Milliseconds")

    def record_guardrail_block(self, block_type: str = "Input") -> None:
        metric = "GuardrailBlockedInputs" if block_type == "Input" else "GuardrailBlockedOutputs"
        self.emit_metric(metric, 1.0, "Count")


metrics = CloudWatchMetrics()
