import logging
import os
import signal
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import yaml
from collectors.ad_health import AdHealthCollector
from collectors.certificate_expiry import CertificateExpiryCollector
from collectors.http_health import HttpHealthCollector
from collectors.system_metrics import SystemMetricsCollector
from prometheus_client import start_http_server
from prometheus_client.core import REGISTRY

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("panoptes-exporter")


class PanoptesCollector:
    def __init__(self, collectors, collection_interval):
        self._collectors = collectors
        self._collection_interval = collection_interval

    def describe(self):
        return []

    def collect(self):
        with ThreadPoolExecutor(max_workers=len(self._collectors)) as executor:
            futures = {
                executor.submit(c.collect): c for c in self._collectors
            }
            for future in as_completed(futures):
                try:
                    future.result(timeout=self._collection_interval)
                except Exception:
                    logger.exception(
                        "Collector %s failed",
                        type(futures[future]).__name__,
                    )
        return []


def load_config():
    config_path = os.environ.get("CONFIG_PATH", "config.yaml")
    with open(config_path) as f:
        return yaml.safe_load(f)


def build_collectors(config):
    collectors = []
    enabled_names = []

    if config.get("http_health", {}).get("enabled", False):
        collectors.append(HttpHealthCollector(config["http_health"]))
        enabled_names.append("http_health")

    if config.get("system_metrics", {}).get("enabled", False):
        collectors.append(SystemMetricsCollector(config["system_metrics"]))
        enabled_names.append("system_metrics")

    if config.get("ad_health", {}).get("enabled", False):
        collectors.append(AdHealthCollector(config["ad_health"]))
        enabled_names.append("ad_health")

    if config.get("certificate_expiry", {}).get("enabled", False):
        collectors.append(CertificateExpiryCollector(config["certificate_expiry"]))
        enabled_names.append("certificate_expiry")

    return collectors, enabled_names


def main():
    config = load_config()
    server_config = config.get("server", {})
    port = server_config.get("port", 9101)
    collection_interval = server_config.get("collection_interval", 15)

    collectors, enabled_names = build_collectors(config)

    logger.info("Starting PANOPTES exporter on port %d", port)
    logger.info("Enabled collectors: %s", ", ".join(enabled_names))

    panoptes_collector = PanoptesCollector(collectors, collection_interval)
    REGISTRY.register(panoptes_collector)

    start_http_server(port)

    shutdown_event = False

    def handle_signal(signum, frame):
        nonlocal shutdown_event
        logger.info("Received signal %d, shutting down", signum)
        shutdown_event = True

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    while not shutdown_event:
        time.sleep(1)

    logger.info("Exporter stopped")
    sys.exit(0)


if __name__ == "__main__":
    main()
