import subprocess
import time

import pytest
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

pytestmark = pytest.mark.integration


def _session_with_retries(retries=3, backoff=1.0):
    session = requests.Session()
    adapter = HTTPAdapter(
        max_retries=Retry(
            total=retries,
            backoff_factor=backoff,
            status_forcelist=[502, 503, 504],
        )
    )
    session.mount("http://", adapter)
    return session


@pytest.fixture()
def http_session():
    return _session_with_retries()


def test_prometheus_targets_up(http_session):
    response = http_session.get(
        "http://localhost:9090/api/v1/targets", timeout=10
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"

    active_targets = data["data"]["activeTargets"]
    assert len(active_targets) > 0

    up_targets = [t for t in active_targets if t["health"] == "up"]
    assert len(up_targets) > 0


def test_grafana_health(http_session):
    response = http_session.get(
        "http://localhost:3000/api/health", timeout=10
    )
    assert response.status_code == 200


def test_alertmanager_health(http_session):
    response = http_session.get(
        "http://localhost:9093/-/healthy", timeout=10
    )
    assert response.status_code == 200


def test_loki_ready(http_session):
    response = http_session.get("http://localhost:3100/ready", timeout=10)
    assert response.status_code == 200


def test_custom_exporter_metrics(http_session):
    response = http_session.get(
        "http://localhost:9101/metrics", timeout=10
    )
    assert response.status_code == 200
    assert "umas_" in response.text


def test_webhook_receiver_health(http_session):
    response = http_session.get("http://localhost:5001/health", timeout=10)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"


def test_alert_fires_on_target_down(http_session):
    container_name = "node-exporter"

    subprocess.run(
        ["docker", "stop", container_name],
        capture_output=True,
        timeout=30,
        check=False,
    )

    try:
        max_wait = 120
        interval = 10
        elapsed = 0
        alert_found = False

        while elapsed < max_wait:
            time.sleep(interval)
            elapsed += interval

            try:
                response = http_session.get(
                    "http://localhost:9093/api/v2/alerts", timeout=10
                )
                if response.status_code == 200:
                    alerts = response.json()
                    for alert in alerts:
                        labels = alert.get("labels", {})
                        if labels.get("alertname") in (
                            "InstanceDown",
                            "PrometheusTargetDown",
                        ):
                            alert_found = True
                            break
            except requests.RequestException:
                pass

            if alert_found:
                break

        assert alert_found, "No alert fired after stopping container"
    finally:
        subprocess.run(
            ["docker", "start", container_name],
            capture_output=True,
            timeout=30,
            check=False,
        )


def test_loki_log_ingestion(http_session):
    params = {
        "query": '{job=~".+"}',
        "limit": 10,
    }

    max_retries = 3
    for attempt in range(max_retries):
        try:
            response = http_session.get(
                "http://localhost:3100/loki/api/v1/query_range",
                params=params,
                timeout=15,
            )
            if response.status_code == 200:
                data = response.json()
                result = data.get("data", {}).get("result", [])
                if len(result) > 0:
                    return
        except requests.RequestException:
            pass

        if attempt < max_retries - 1:
            time.sleep(5)

    pytest.fail("No logs found in Loki after retries")
