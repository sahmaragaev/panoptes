import os
import shutil
import subprocess
import tempfile

import pytest
import yaml

PROMTOOL_AVAILABLE = shutil.which("promtool") is not None
ALERT_RULES_PATH = os.path.join(
    os.path.dirname(__file__), "..", "configs", "prometheus", "alert_rules.yml"
)


@pytest.mark.skipif(not PROMTOOL_AVAILABLE, reason="promtool not installed")
def test_alert_rules_syntax():
    result = subprocess.run(
        ["promtool", "check", "rules", ALERT_RULES_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"promtool check rules failed:\n{result.stderr}"


@pytest.mark.skipif(not PROMTOOL_AVAILABLE, reason="promtool not installed")
def test_instance_down_fires():
    test_config = {
        "rule_files": [ALERT_RULES_PATH],
        "evaluation_interval": "1m",
        "tests": [
            {
                "interval": "1m",
                "input_series": [
                    {
                        "series": 'up{job="node-exporter", instance="localhost:9100"}',
                        "values": "0x10",
                    }
                ],
                "alert_rule_test": [
                    {
                        "eval_time": "2m",
                        "alertname": "InstanceDown",
                        "exp_alerts": [
                            {
                                "exp_labels": {
                                    "job": "node-exporter",
                                    "instance": "localhost:9100",
                                    "severity": "critical",
                                },
                                "exp_annotations": {
                                    "summary": "Instance localhost:9100 is down",
                                    "description": "The instance localhost:9100 has been unreachable for more than 1 minute.",
                                    "runbook_url": "docs/runbook.md#instance-down",
                                },
                            }
                        ],
                    }
                ],
            }
        ],
    }

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".yml", delete=False
    ) as f:
        yaml.dump(test_config, f, default_flow_style=False)
        test_file = f.name

    try:
        result = subprocess.run(
            ["promtool", "test", "rules", test_file],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"InstanceDown test failed:\n{result.stdout}\n{result.stderr}"
        )
    finally:
        os.unlink(test_file)


@pytest.mark.skipif(not PROMTOOL_AVAILABLE, reason="promtool not installed")
def test_disk_space_critical_fires():
    test_config = {
        "rule_files": [ALERT_RULES_PATH],
        "evaluation_interval": "1m",
        "tests": [
            {
                "interval": "1m",
                "input_series": [
                    {
                        "series": 'node_filesystem_avail_bytes{instance="localhost:9100", fstype="ext4", mountpoint="/"}',
                        "values": "5000000000x10",
                    },
                    {
                        "series": 'node_filesystem_size_bytes{instance="localhost:9100", fstype="ext4", mountpoint="/"}',
                        "values": "100000000000x10",
                    },
                ],
                "alert_rule_test": [
                    {
                        "eval_time": "6m",
                        "alertname": "DiskSpaceCritical",
                        "exp_alerts": [
                            {
                                "exp_labels": {
                                    "instance": "localhost:9100",
                                    "fstype": "ext4",
                                    "mountpoint": "/",
                                    "severity": "critical",
                                    "remediation": "disk_cleanup",
                                },
                                "exp_annotations": {
                                    "summary": "Critical disk space on localhost:9100",
                                    "description": "Disk usage on localhost:9100 (/) has been above 90% for 5 minutes. Current value: 95.00%.",
                                    "runbook_url": "docs/runbook.md#disk-space-critical",
                                },
                            }
                        ],
                    }
                ],
            }
        ],
    }

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".yml", delete=False
    ) as f:
        yaml.dump(test_config, f, default_flow_style=False)
        test_file = f.name

    try:
        result = subprocess.run(
            ["promtool", "test", "rules", test_file],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"DiskSpaceCritical test failed:\n{result.stdout}\n{result.stderr}"
        )
    finally:
        os.unlink(test_file)


@pytest.mark.skipif(not PROMTOOL_AVAILABLE, reason="promtool not installed")
def test_high_cpu_usage_fires():
    test_config = {
        "rule_files": [ALERT_RULES_PATH],
        "evaluation_interval": "1m",
        "tests": [
            {
                "interval": "1m",
                "input_series": [
                    {
                        "series": 'node_cpu_seconds_total{instance="localhost:9100", mode="idle", cpu="0"}',
                        "values": "0+0.1x10",
                    },
                ],
                "alert_rule_test": [
                    {
                        "eval_time": "6m",
                        "alertname": "HighCPUUsage",
                        "exp_alerts": [
                            {
                                "exp_labels": {
                                    "instance": "localhost:9100",
                                    "severity": "warning",
                                },
                            }
                        ],
                    }
                ],
            }
        ],
    }

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".yml", delete=False
    ) as f:
        yaml.dump(test_config, f, default_flow_style=False)
        test_file = f.name

    try:
        result = subprocess.run(
            ["promtool", "test", "rules", test_file],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"HighCPUUsage test failed:\n{result.stdout}\n{result.stderr}"
        )
    finally:
        os.unlink(test_file)
