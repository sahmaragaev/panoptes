import sys
import os
from unittest.mock import patch, MagicMock

import pytest

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(__file__), "..", "remediation", "webhook-receiver"
    ),
)

with patch("builtins.open", MagicMock()), patch(
    "yaml.safe_load",
    return_value={
        "cooldown": {"duration_minutes": 30},
        "ansible": {
            "playbook_dir": "/app/ansible/playbooks",
            "inventory": "/app/ansible/inventory/hosts.yml",
        },
        "logging": {"file": "/dev/null", "level": "INFO"},
    },
):
    import receiver

from fastapi.testclient import TestClient

client = TestClient(receiver.app)

SAMPLE_ALERT_PAYLOAD = {
    "version": "4",
    "groupKey": "test",
    "status": "firing",
    "receiver": "webhook-remediation",
    "alerts": [
        {
            "status": "firing",
            "labels": {
                "alertname": "DiskSpaceCritical",
                "severity": "critical",
                "instance": "panoptes-vps:9100",
                "remediation": "disk_cleanup",
            },
            "annotations": {
                "summary": "Disk space critical on panoptes-vps:9100",
                "description": "Disk usage is above 90%",
            },
            "startsAt": "2026-01-01T00:00:00Z",
            "endsAt": "0001-01-01T00:00:00Z",
        }
    ],
}


@pytest.fixture(autouse=True)
def _reset_state():
    receiver.cooldowns.clear()
    receiver.history.clear()
    yield
    receiver.cooldowns.clear()
    receiver.history.clear()


@patch("receiver.subprocess.run")
def test_webhook_valid_payload(mock_run):
    mock_run.return_value = MagicMock(returncode=0, stdout="ok", stderr="")

    response = client.post("/webhook", json=SAMPLE_ALERT_PAYLOAD)

    assert response.status_code == 200
    data = response.json()
    assert len(data["results"]) == 1
    assert data["results"][0]["remediation"] == "disk_cleanup"
    assert data["results"][0]["target_host"] == "panoptes-vps"


@patch("receiver.subprocess.run")
def test_webhook_cooldown(mock_run):
    mock_run.return_value = MagicMock(returncode=0, stdout="ok", stderr="")

    first_response = client.post("/webhook", json=SAMPLE_ALERT_PAYLOAD)
    assert first_response.status_code == 200

    second_response = client.post("/webhook", json=SAMPLE_ALERT_PAYLOAD)
    assert second_response.status_code == 200
    data = second_response.json()
    assert data["results"][0]["status"] == "skipped"
    assert data["results"][0]["reason"] == "cooldown active"


@patch("receiver.subprocess.run")
def test_webhook_unknown_remediation(mock_run):
    payload = {
        "version": "4",
        "groupKey": "test",
        "status": "firing",
        "receiver": "webhook-remediation",
        "alerts": [
            {
                "status": "firing",
                "labels": {
                    "alertname": "TestAlert",
                    "severity": "warning",
                    "instance": "host1:9100",
                    "remediation": "unknown_type",
                },
                "annotations": {
                    "summary": "Test alert",
                    "description": "Testing unknown remediation",
                },
                "startsAt": "2026-01-01T00:00:00Z",
                "endsAt": "0001-01-01T00:00:00Z",
            }
        ],
    }

    response = client.post("/webhook", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["results"][0]["status"] == "skipped"
    assert "unknown remediation" in data["results"][0]["reason"]


def test_webhook_no_remediation_label():
    payload = {
        "version": "4",
        "groupKey": "test",
        "status": "firing",
        "receiver": "webhook-remediation",
        "alerts": [
            {
                "status": "firing",
                "labels": {
                    "alertname": "HighCPU",
                    "severity": "warning",
                    "instance": "host1:9100",
                },
                "annotations": {
                    "summary": "High CPU usage",
                    "description": "CPU above 90%",
                },
                "startsAt": "2026-01-01T00:00:00Z",
                "endsAt": "0001-01-01T00:00:00Z",
            }
        ],
    }

    response = client.post("/webhook", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["results"][0]["status"] == "skipped"
    assert data["results"][0]["reason"] == "no remediation label"


def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


@patch("receiver.subprocess.run")
def test_history_endpoint(mock_run):
    mock_run.return_value = MagicMock(returncode=0, stdout="ok", stderr="")

    client.post("/webhook", json=SAMPLE_ALERT_PAYLOAD)

    response = client.get("/history")
    assert response.status_code == 200
    data = response.json()
    assert len(data["history"]) == 1
    assert data["history"][0]["alert"] == "DiskSpaceCritical"
    assert data["history"][0]["remediation"] == "disk_cleanup"
    assert data["history"][0]["target_host"] == "panoptes-vps"


@patch("receiver.subprocess.run")
def test_cooldowns_endpoint(mock_run):
    mock_run.return_value = MagicMock(returncode=0, stdout="ok", stderr="")

    client.post("/webhook", json=SAMPLE_ALERT_PAYLOAD)

    response = client.get("/cooldowns")
    assert response.status_code == 200
    data = response.json()
    assert "panoptes-vps:disk_cleanup" in data["cooldowns"]
    cooldown_entry = data["cooldowns"]["panoptes-vps:disk_cleanup"]
    assert "remaining_seconds" in cooldown_entry
    assert cooldown_entry["remaining_seconds"] > 0


def test_webhook_empty_alerts():
    payload = {
        "version": "4",
        "groupKey": "test",
        "status": "firing",
        "receiver": "webhook-remediation",
        "alerts": [],
    }

    response = client.post("/webhook", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["results"] == []
