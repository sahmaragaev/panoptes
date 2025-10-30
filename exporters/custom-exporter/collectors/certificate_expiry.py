import logging
import socket
import ssl
from datetime import datetime, timezone

from prometheus_client import Gauge

logger = logging.getLogger("panoptes-exporter.certificate_expiry")

CERT_EXPIRY_DAYS = Gauge(
    "panoptes_cert_expiry_days",
    "Days until the TLS certificate expires",
    ["host", "port"],
)
CERT_VALID = Gauge(
    "panoptes_cert_valid",
    "Whether the TLS certificate is valid",
    ["host", "port"],
)


class CertificateExpiryCollector:
    def __init__(self, config):
        self._hosts = config.get("hosts", [])

    def _check_certificate(self, entry):
        host = entry["host"]
        port = entry.get("port", 443)
        port_str = str(port)
        try:
            context = ssl.create_default_context()
            with socket.create_connection((host, port), timeout=10) as sock:
                with context.wrap_socket(sock, server_hostname=host) as ssock:
                    cert = ssock.getpeercert()

            not_after = datetime.strptime(
                cert["notAfter"], "%b %d %H:%M:%S %Y %Z"
            ).replace(tzinfo=timezone.utc)
            now = datetime.now(timezone.utc)
            days_remaining = (not_after - now).days

            CERT_EXPIRY_DAYS.labels(host=host, port=port_str).set(
                days_remaining
            )
            CERT_VALID.labels(host=host, port=port_str).set(
                1 if days_remaining > 0 else 0
            )
        except Exception:
            logger.warning(
                "Certificate check failed for %s:%d", host, port
            )
            CERT_EXPIRY_DAYS.labels(host=host, port=port_str).set(-1)
            CERT_VALID.labels(host=host, port=port_str).set(0)

    def collect(self):
        for entry in self._hosts:
            self._check_certificate(entry)
