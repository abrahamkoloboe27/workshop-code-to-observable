"""Prometheus instrumentation."""

from prometheus_client import Counter, Histogram

ORDERS_REQUESTS = Counter(
    "orders_requests_total",
    "Number of requests served by GET /orders",
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    labelnames=("method", "path", "status"),
)
