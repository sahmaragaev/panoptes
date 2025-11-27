import os
import sys
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, mock_open, patch

import pytest
import yaml

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(__file__), "..", "exporters", "custom-exporter"
    ),
)

from collectors.ad_health import AdHealthCollector
from collectors.certificate_expiry import CertificateExpiryCollector
from collectors.http_health import HttpHealthCollector
from collectors.system_metrics import SystemMetricsCollector
from exporter import build_collectors, load_config


@pytest.fixture()
def http_health_config():
    return {
        "endpoints": [
            {"name": "test-service", "url": "http://localhost:8080/health"}
        ],
        "timeout": 5,
    }


@pytest.fixture()
def system_metrics_config():
    return {"auth_log_path": "/var/log/auth.log"}


@pytest.fixture()
def certificate_config():
    return {
        "hosts": [
            {"host": "example.com", "port": 443},
        ]
    }


@pytest.fixture()
def full_config():
    return {
        "server": {"port": 9101, "collection_interval": 15},
        "http_health": {
            "enabled": True,
            "timeout": 5,
            "endpoints": [
                {"name": "grafana", "url": "http://grafana:3000/api/health"}
            ],
        },
        "system_metrics": {
            "enabled": True,
            "auth_log_path": "/var/log/auth.log",
        },
        "ad_health": {
            "enabled": False,
            "domain_controllers": [{"host": "dc01.local", "port": 636}],
            "domain": "local",
        },
        "certificate_expiry": {
            "enabled": True,
            "hosts": [{"host": "example.com", "port": 443}],
        },
    }


@patch("collectors.http_health.ENDPOINT_UP")
@patch("collectors.http_health.ENDPOINT_STATUS_CODE")
@patch("collectors.http_health.ENDPOINT_RESPONSE_SECONDS")
@patch("collectors.http_health.requests.get")
def test_http_health_collector_success(
    mock_get,
    mock_response_seconds,
    mock_status_code,
    mock_up,
    http_health_config,
):
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.elapsed.total_seconds.return_value = 0.05
    mock_get.return_value = mock_response

    collector = HttpHealthCollector(http_health_config)
    collector.collect()

    mock_up.labels(name="test-service", url="http://localhost:8080/health").set.assert_called_with(1)
    mock_response_seconds.labels(name="test-service").observe.assert_called_with(0.05)


@patch("collectors.http_health.ENDPOINT_UP")
@patch("collectors.http_health.ENDPOINT_STATUS_CODE")
@patch("collectors.http_health.requests.get")
def test_http_health_collector_timeout(
    mock_get,
    mock_status_code,
    mock_up,
    http_health_config,
):
    import requests

    mock_get.side_effect = requests.exceptions.Timeout("Connection timed out")

    collector = HttpHealthCollector(http_health_config)
    collector.collect()

    mock_up.labels(name="test-service", url="http://localhost:8080/health").set.assert_called_with(0)


@patch("collectors.http_health.ENDPOINT_UP")
@patch("collectors.http_health.ENDPOINT_STATUS_CODE")
@patch("collectors.http_health.requests.get")
def test_http_health_collector_connection_error(
    mock_get,
    mock_status_code,
    mock_up,
    http_health_config,
):
    import requests

    mock_get.side_effect = requests.exceptions.ConnectionError("Connection refused")

    collector = HttpHealthCollector(http_health_config)
    collector.collect()

    mock_up.labels(name="test-service", url="http://localhost:8080/health").set.assert_called_with(0)


@patch("collectors.system_metrics.PROCESS_COUNT")
@patch("collectors.system_metrics.os.listdir")
def test_system_metrics_process_count(
    mock_listdir,
    mock_process_count,
    system_metrics_config,
):
    mock_listdir.return_value = ["1", "2", "3", "self", "meminfo"]

    collector = SystemMetricsCollector(system_metrics_config)

    with patch("builtins.open", side_effect=FileNotFoundError):
        collector._collect_process_counts()

    mock_process_count.set.assert_called_with(3)


@patch("collectors.system_metrics.ZOMBIE_COUNT")
@patch("collectors.system_metrics.PROCESS_COUNT")
@patch("collectors.system_metrics.os.listdir")
def test_system_metrics_zombie_count(
    mock_listdir,
    mock_process_count,
    mock_zombie_count,
    system_metrics_config,
):
    mock_listdir.return_value = ["1", "2", "3"]

    status_contents = {
        "/proc/1/status": "Name:\tinit\nState:\tS (sleeping)\n",
        "/proc/2/status": "Name:\tzombie_proc\nState:\tZ (zombie)\n",
        "/proc/3/status": "Name:\tbash\nState:\tR (running)\n",
    }

    def open_side_effect(path, *args, **kwargs):
        if path in status_contents:
            return mock_open(read_data=status_contents[path])()
        raise FileNotFoundError(path)

    collector = SystemMetricsCollector(system_metrics_config)

    with patch("builtins.open", side_effect=open_side_effect):
        collector._collect_process_counts()

    mock_zombie_count.set.assert_called_with(1)


@patch("collectors.system_metrics.FD_USAGE_RATIO")
def test_system_metrics_fd_usage(mock_fd_ratio, system_metrics_config):
    collector = SystemMetricsCollector(system_metrics_config)

    file_nr_data = "5000\t0\t100000\n"
    m = mock_open(read_data=file_nr_data)

    with patch("builtins.open", m):
        collector._collect_fd_usage()

    mock_fd_ratio.set.assert_called_with(5000 / 100000)


@patch("collectors.certificate_expiry.CERT_VALID")
@patch("collectors.certificate_expiry.CERT_EXPIRY_DAYS")
@patch("collectors.certificate_expiry.socket.create_connection")
@patch("collectors.certificate_expiry.ssl.create_default_context")
def test_certificate_expiry_valid(
    mock_ssl_context,
    mock_create_conn,
    mock_expiry_days,
    mock_cert_valid,
    certificate_config,
):
    future_date = datetime.now(timezone.utc) + timedelta(days=30)
    not_after_str = future_date.strftime("%b %d %H:%M:%S %Y GMT")

    mock_cert = {"notAfter": not_after_str}
    mock_ssock = MagicMock()
    mock_ssock.getpeercert.return_value = mock_cert
    mock_ssock.__enter__ = MagicMock(return_value=mock_ssock)
    mock_ssock.__exit__ = MagicMock(return_value=False)

    mock_context = MagicMock()
    mock_context.wrap_socket.return_value = mock_ssock
    mock_ssl_context.return_value = mock_context

    mock_sock = MagicMock()
    mock_sock.__enter__ = MagicMock(return_value=mock_sock)
    mock_sock.__exit__ = MagicMock(return_value=False)
    mock_create_conn.return_value = mock_sock

    collector = CertificateExpiryCollector(certificate_config)
    collector.collect()

    mock_expiry_days.labels(host="example.com", port="443").set.assert_called()
    actual_days = mock_expiry_days.labels(host="example.com", port="443").set.call_args[0][0]
    assert 29 <= actual_days <= 30

    mock_cert_valid.labels(host="example.com", port="443").set.assert_called_with(1)


@patch("collectors.certificate_expiry.CERT_VALID")
@patch("collectors.certificate_expiry.CERT_EXPIRY_DAYS")
@patch("collectors.certificate_expiry.socket.create_connection")
@patch("collectors.certificate_expiry.ssl.create_default_context")
def test_certificate_expiry_expired(
    mock_ssl_context,
    mock_create_conn,
    mock_expiry_days,
    mock_cert_valid,
    certificate_config,
):
    past_date = datetime.now(timezone.utc) - timedelta(days=5)
    not_after_str = past_date.strftime("%b %d %H:%M:%S %Y GMT")

    mock_cert = {"notAfter": not_after_str}
    mock_ssock = MagicMock()
    mock_ssock.getpeercert.return_value = mock_cert
    mock_ssock.__enter__ = MagicMock(return_value=mock_ssock)
    mock_ssock.__exit__ = MagicMock(return_value=False)

    mock_context = MagicMock()
    mock_context.wrap_socket.return_value = mock_ssock
    mock_ssl_context.return_value = mock_context

    mock_sock = MagicMock()
    mock_sock.__enter__ = MagicMock(return_value=mock_sock)
    mock_sock.__exit__ = MagicMock(return_value=False)
    mock_create_conn.return_value = mock_sock

    collector = CertificateExpiryCollector(certificate_config)
    collector.collect()

    mock_cert_valid.labels(host="example.com", port="443").set.assert_called_with(0)


@patch("collectors.certificate_expiry.CERT_VALID")
@patch("collectors.certificate_expiry.CERT_EXPIRY_DAYS")
@patch("collectors.certificate_expiry.socket.create_connection")
@patch("collectors.certificate_expiry.ssl.create_default_context")
def test_certificate_expiry_connection_error(
    mock_ssl_context,
    mock_create_conn,
    mock_expiry_days,
    mock_cert_valid,
    certificate_config,
):
    mock_create_conn.side_effect = ConnectionRefusedError("Connection refused")

    collector = CertificateExpiryCollector(certificate_config)
    collector.collect()

    mock_cert_valid.labels(host="example.com", port="443").set.assert_called_with(0)
    mock_expiry_days.labels(host="example.com", port="443").set.assert_called_with(-1)


def test_config_loading(tmp_path):
    config_data = {
        "server": {"port": 9101, "collection_interval": 15},
        "http_health": {"enabled": True, "timeout": 5, "endpoints": []},
        "system_metrics": {"enabled": False},
        "ad_health": {"enabled": False},
        "certificate_expiry": {"enabled": False},
    }

    config_file = tmp_path / "test_config.yaml"
    config_file.write_text(yaml.dump(config_data))

    with patch.dict(os.environ, {"CONFIG_PATH": str(config_file)}):
        loaded = load_config()

    assert loaded["server"]["port"] == 9101
    assert loaded["http_health"]["enabled"] is True
    assert loaded["system_metrics"]["enabled"] is False


def test_ad_health_disabled(full_config):
    full_config["ad_health"]["enabled"] = False

    collectors, enabled_names = build_collectors(full_config)

    assert "ad_health" not in enabled_names
    for c in collectors:
        assert not isinstance(c, AdHealthCollector)
