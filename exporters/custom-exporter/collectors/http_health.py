import logging
from concurrent.futures import ThreadPoolExecutor

import requests
from prometheus_client import Gauge, Histogram

logger = logging.getLogger("panoptes-exporter.http_health")

ENDPOINT_UP = Gauge(
    "panoptes_endpoint_up",
    "Whether the endpoint is reachable",
    ["name"],
)
ENDPOINT_RESPONSE_SECONDS = Histogram(
    "panoptes_endpoint_response_seconds",
    "HTTP response time in seconds",
    ["name"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)
ENDPOINT_STATUS_CODE = Gauge(
    "panoptes_endpoint_status_code",
    "HTTP status code of the endpoint",
    ["name"],
)


class HttpHealthCollector:
    def __init__(self, config):
        self._endpoints = config.get("endpoints", [])
        self._timeout = config.get("timeout", 5)

    def _check_endpoint(self, endpoint):
        name = endpoint["name"]
        url = endpoint["url"]
        try:
            response = requests.get(url, timeout=self._timeout)
            ENDPOINT_UP.labels(name=name).set(1)
            ENDPOINT_STATUS_CODE.labels(name=name).set(
                response.status_code
            )
            ENDPOINT_RESPONSE_SECONDS.labels(name=name).observe(
                response.elapsed.total_seconds()
            )
        except requests.exceptions.RequestException:
            logger.warning("Endpoint %s (%s) is unreachable", name, url)
            ENDPOINT_UP.labels(name=name).set(0)
            ENDPOINT_STATUS_CODE.labels(name=name).set(0)

    def collect(self):
        with ThreadPoolExecutor(max_workers=len(self._endpoints)) as executor:
            executor.map(self._check_endpoint, self._endpoints)
