import logging
import socket
import time

from ldap3 import Connection, Server, Tls
from prometheus_client import Gauge

logger = logging.getLogger("umas-exporter.ad_health")

AD_LDAP_BIND_SECONDS = Gauge(
    "umas_ad_ldap_bind_seconds",
    "Time to bind to the domain controller via LDAP",
    ["dc"],
)
AD_DNS_RESOLUTION_UP = Gauge(
    "umas_ad_dns_resolution_up",
    "Whether DNS resolution for the domain is working",
    ["domain"],
)
AD_REPLICATION_PARTNER_UP = Gauge(
    "umas_ad_replication_partner_up",
    "Whether the replication partner is reachable",
    ["dc"],
)


class AdHealthCollector:
    def __init__(self, config):
        self._domain_controllers = config.get("domain_controllers", [])
        self._domain = config.get("domain", "")

    def _check_ldap_bind(self, dc):
        host = dc["host"]
        port = dc.get("port", 636)
        try:
            tls = Tls(validate=0)
            server = Server(host, port=port, use_ssl=True, tls=tls)
            start = time.time()
            conn = Connection(server, auto_bind=True)
            elapsed = time.time() - start
            AD_LDAP_BIND_SECONDS.labels(dc=host).set(elapsed)
            AD_REPLICATION_PARTNER_UP.labels(dc=host).set(1)
            conn.unbind()
        except Exception:
            logger.warning("LDAP bind to %s:%d failed", host, port)
            AD_LDAP_BIND_SECONDS.labels(dc=host).set(-1)
            AD_REPLICATION_PARTNER_UP.labels(dc=host).set(0)

    def _check_dns_resolution(self):
        srv_record = f"_ldap._tcp.{self._domain}"
        try:
            socket.getaddrinfo(srv_record, None)
            AD_DNS_RESOLUTION_UP.labels(domain=self._domain).set(1)
        except socket.gaierror:
            logger.warning("DNS resolution failed for %s", srv_record)
            AD_DNS_RESOLUTION_UP.labels(domain=self._domain).set(0)

    def collect(self):
        for dc in self._domain_controllers:
            self._check_ldap_bind(dc)
        self._check_dns_resolution()
