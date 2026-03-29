# UMAS Alert Rules Reference

Complete reference for all 26 alert rules configured in UMAS, including expressions, thresholds, routing behavior, and guidance on creating custom alerts.

---

## Table of Contents

1. [Alert Rules Table](#alert-rules-table)
2. [Alert Severity Levels](#alert-severity-levels)
3. [Alert Routing](#alert-routing)
4. [Inhibition Rules](#inhibition-rules)
5. [Adding Custom Alerts](#adding-custom-alerts)
6. [Silencing Alerts](#silencing-alerts)
7. [Testing Alert Rules](#testing-alert-rules)

---

## Alert Rules Table

### Host Alerts (`host_alerts` group)

| Alert Name | Severity | Expression (Summary) | For | Description | Auto-Remediation |
|---|---|---|---|---|---|
| InstanceDown | critical | `up == 0` | 1m | A monitored target is unreachable and not responding to Prometheus scrapes. | No |
| HighCPUUsage | warning | CPU idle < 15% (usage > 85%) | 5m | CPU utilization has been above 85% for 5 minutes. | No |
| CriticalCPUUsage | critical | CPU idle < 5% (usage > 95%) | 2m | CPU utilization has been above 95% for 2 minutes. Immediate attention required. | No |
| HighMemoryUsage | warning | Available memory < 15% (usage > 85%) | 5m | Memory utilization has been above 85% for 5 minutes. | No |
| HostOutOfMemory | critical | Available memory < 10% | 2m | Host is critically low on memory. Processes may be killed by OOM killer. | Yes (`clear_memory`) |
| DiskSpaceWarning | warning | Disk usage > 80% | 10m | Disk utilization has been above 80% for 10 minutes. Excludes tmpfs and overlay filesystems. | No |
| DiskSpaceCritical | critical | Disk usage > 90% | 5m | Disk utilization has been above 90% for 5 minutes. Service disruption is imminent. | Yes (`disk_cleanup`) |
| DiskFillingUp | warning | `predict_linear` forecasts disk full within 24h | 30m | Based on the last 6 hours of data, the disk is predicted to fill within 24 hours. | No |
| HighSystemLoad | warning | 1-minute load average > CPU count | 10m | System load exceeds the number of available CPUs for 10 minutes. | No |
| TooManyOpenFiles | warning | File descriptor usage > 80% | 5m | The ratio of allocated file descriptors to the system maximum exceeds 80%. | No |
| NetworkReceiveErrors | warning | Receive error rate > 0/s | 5m | A network interface is experiencing persistent receive errors. | No |
| HighSwapUsage | warning | Swap usage > 80% | 5m | Swap utilization has been above 80% for 5 minutes. Indicates memory pressure. | No |
| SystemdServiceFailed | critical | `node_systemd_unit_state{state="failed"} == 1` | 2m | A systemd service has entered a failed state. | Yes (`restart_service`) |
| HostClockSkew | warning | Time offset > 50ms | 5m | System clock is skewed by more than 50 milliseconds. May cause certificate validation failures and log timestamp inconsistencies. | No |
| OOMKillDetected | warning | `increase(node_vmstat_oom_kill[5m]) > 0` | 0m | An OOM (Out of Memory) kill event was detected. A process was terminated by the kernel. | No |

### Container Alerts (`container_alerts` group)

| Alert Name | Severity | Expression (Summary) | For | Description | Auto-Remediation |
|---|---|---|---|---|---|
| ContainerHighCPU | warning | Container CPU usage > 80% | 5m | A container is using more than 80% CPU for 5 minutes. | No |
| ContainerHighMemory | warning | Container memory > 85% of limit | 5m | A container is using more than 85% of its configured memory limit. | No |
| ContainerRestarting | warning | Restart count increase > 3 in 10m | 0m | A container has restarted more than 3 times in the last 10 minutes. Indicates a crash loop. | No |
| ContainerKilled | critical | `container_oom_events_total > 0` | 0m | A container was killed due to an out-of-memory event. | No |

### Monitoring Stack Alerts (`monitoring_stack_alerts` group)

| Alert Name | Severity | Expression (Summary) | For | Description | Auto-Remediation |
|---|---|---|---|---|---|
| PrometheusTargetDown | critical | `up{job=~"prometheus\|alertmanager\|grafana\|loki"} == 0` | 3m | A core monitoring stack component is unreachable. Self-monitoring has detected an internal failure. | No |
| PrometheusHighMemory | warning | Prometheus RSS > 80% of 512 MB limit | 5m | Prometheus memory usage is approaching its configured limit. May cause OOMKill. | No |
| AlertmanagerNotificationFailed | critical | `rate(alertmanager_notifications_failed_total[5m]) > 0` | 1m | Alertmanager is failing to deliver notifications. Alert routing may be broken. | No |
| LokiIngestionRate | warning | `rate(loki_distributor_lines_received_total[5m]) == 0` | 5m | Loki has not ingested any log lines in 5 minutes. Log pipeline may be broken. | No |
| GrafanaDown | critical | `up{job="grafana"} == 0` | 2m | Grafana is unreachable. Dashboards and visualization are unavailable. | No |

### Predictive Alerts (`predictive_alerts` group)

| Alert Name | Severity | Expression (Summary) | For | Description | Auto-Remediation |
|---|---|---|---|---|---|
| DiskWillFillIn4Hours | critical | `predict_linear` forecasts disk full within 4h | 15m | Based on the last hour of data, the disk is predicted to fill within 4 hours. Urgent action required. | No |
| MemoryLeakDetected | warning | `deriv(process_resident_memory_bytes[1h]) > 1048576` | 30m | A process shows a steady memory increase exceeding 1 MB/s over the last hour. Likely a memory leak. | No |

---

## Alert Severity Levels

UMAS uses two severity levels that determine notification routing and urgency.

### Warning

- **Color**: Yellow/Orange
- **Notification channel**: Slack (`#umas-alerts`)
- **Repeat interval**: Every 4 hours
- **Meaning**: A condition that requires attention but is not immediately service-impacting. The operations team should investigate during business hours.
- **Examples**: High CPU usage, disk space above 80%, memory pressure, network errors

### Critical

- **Color**: Red
- **Notification channel**: Slack (`#umas-critical`) **AND** Telegram
- **Repeat interval**: Every 1 hour
- **Meaning**: A condition that is actively impacting service availability or will do so imminently. Requires immediate response.
- **Examples**: Instance unreachable, disk above 90%, OOM kills, monitoring stack failures

---

## Alert Routing

Alert routing is defined in `configs/alertmanager/alertmanager.yml`. The routing tree works as follows:

```
All alerts
    |
    |--> Default receiver: slack-warnings
    |    (group_wait: 30s, group_interval: 5m, repeat_interval: 4h)
    |
    |--> Match: severity=critical --> critical-multi receiver
    |    (repeat_interval: 1h)
    |    Sends to: Slack #umas-critical + Telegram
    |
    |--> Match: remediation=.+ --> webhook-remediation receiver
         (group_wait: 10s, continue: true)
         Sends to: Webhook Receiver at http://webhook-receiver:5001/webhook
         NOTE: "continue: true" means the alert also matches other routes
```

### Grouping

Alerts are grouped by three labels: `alertname`, `severity`, and `instance`. This means:

- Multiple alerts of the same type on the same instance are sent as a single notification
- Different alert types on the same instance are sent separately
- The initial notification is delayed by 30 seconds (`group_wait`) to batch alerts that fire together

### Receivers

| Receiver | Channel | Configuration |
|---|---|---|
| `slack-warnings` | Slack `#umas-alerts` | Warning-level alerts, resolved notifications enabled |
| `critical-multi` | Slack `#umas-critical` + Telegram | Critical-level alerts, resolved notifications enabled |
| `webhook-remediation` | HTTP POST to webhook-receiver:5001 | Alerts with `remediation` label, resolved notifications disabled |

---

## Inhibition Rules

Inhibition rules prevent notification noise during cascading failures.

### Rule 1: Critical Suppresses Warning

```yaml
source_matchers:
  - severity = critical
target_matchers:
  - severity = warning
equal: ['alertname', 'instance']
```

When both a critical and warning alert fire for the **same alertname and instance**, the warning notification is suppressed. For example, if `DiskSpaceCritical` (>90%) fires, `DiskSpaceWarning` (>80%) is silenced because the critical alert already covers the situation.

### Rule 2: InstanceDown Suppresses All

```yaml
source_matchers:
  - alertname = InstanceDown
target_matchers:
  - severity =~ ".*"
equal: ['instance']
```

When `InstanceDown` fires for an instance, **all other alerts** for that same instance are suppressed. This prevents a flood of CPU/memory/disk alerts when the real problem is that the host is unreachable.

---

## Adding Custom Alerts

To add a new alert rule:

### Step 1: Edit the Alert Rules File

Open `configs/prometheus/alert_rules.yml` and add a new rule to the appropriate group (or create a new group).

**Example: High network bandwidth usage**

```yaml
groups:
  - name: host_alerts
    rules:
      # ... existing rules ...

      - alert: HighNetworkBandwidth
        expr: rate(node_network_receive_bytes_total{device="eth0"}[5m]) > 100000000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High network receive bandwidth on {{ $labels.instance }}"
          description: "Network receive rate on {{ $labels.instance }} exceeds 100 MB/s for 5 minutes. Current rate: {{ $value | humanize }}B/s."
          runbook_url: "docs/runbook.md#high-network-bandwidth"
```

### Step 2: Add a Remediation Label (Optional)

If you want automatic remediation for the alert, add a `remediation` label that maps to a key in the webhook receiver's `PLAYBOOK_MAP`:

```yaml
labels:
  severity: critical
  remediation: docker_cleanup    # Must match a key in PLAYBOOK_MAP
```

### Step 3: Validate the Rules

```bash
promtool check rules configs/prometheus/alert_rules.yml
```

### Step 4: Reload Prometheus

```bash
# Via lifecycle API
curl -X POST http://localhost:9090/-/reload

# Or restart the container
docker compose restart prometheus
```

### Step 5: Verify

Open http://localhost:9090/rules and confirm the new rule appears.

### Rule Writing Tips

- Use `rate()` for counters (e.g., `node_cpu_seconds_total`, `node_network_receive_bytes_total`)
- Use raw values for gauges (e.g., `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes`)
- Set `for` duration to avoid flapping: use 0m for instant events (OOM), 2-5m for transient spikes, 10-30m for trends
- Use `predict_linear()` for predictive alerts
- Exclude filesystem types like `tmpfs` and `overlay` to avoid false positives on container mounts
- Always include `summary` and `description` annotations with `{{ $labels.instance }}` and `{{ $value }}` templates
- Add a `runbook_url` annotation linking to the runbook entry

---

## Silencing Alerts

Silences temporarily suppress notifications for specific alerts. They do **not** stop Prometheus from evaluating rules -- the alerts still fire, but Alertmanager does not send notifications.

### Via the Alertmanager UI

1. Open http://localhost:9093/#/silences
2. Click **New Silence**
3. Set matchers (e.g., `alertname=HighCPUUsage`, `instance=node-exporter:9100`)
4. Set the duration (start and end time)
5. Add a comment explaining why the silence is in place
6. Click **Create**

### Via the Alertmanager API

```bash
curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {"name": "alertname", "value": "HighCPUUsage", "isRegex": false}
    ],
    "startsAt": "2026-03-28T00:00:00Z",
    "endsAt": "2026-03-28T06:00:00Z",
    "createdBy": "operator",
    "comment": "Maintenance window: planned CPU-intensive batch job"
  }'
```

### Best Practices for Silences

- Always add a descriptive comment
- Set the shortest duration necessary
- Use specific matchers (alertname + instance) rather than broad matchers (severity only)
- Review active silences regularly -- expired silences are cleaned up automatically
- Do not silence `InstanceDown` or `PrometheusTargetDown` during maintenance; instead, remove the target from the scrape configuration temporarily

---

## Testing Alert Rules

### Unit Testing with promtool

Create a test file (`configs/prometheus/alert_rules_test.yml`):

```yaml
rule_files:
  - alert_rules.yml

evaluation_interval: 15s

tests:
  - interval: 1m
    input_series:
      - series: 'up{job="node-exporter", instance="node-exporter:9100"}'
        values: '1 1 1 0 0 0 0'
    alert_rule_test:
      - eval_time: 5m
        alertname: InstanceDown
        exp_alerts:
          - exp_labels:
              severity: critical
              job: node-exporter
              instance: "node-exporter:9100"
            exp_annotations:
              summary: "Instance node-exporter:9100 is down"
```

Run:

```bash
promtool test rules configs/prometheus/alert_rules_test.yml
```

### Manual Testing

Use the simulation scripts in `remediation/scripts/` to trigger alerts in a live deployment:

```bash
# Trigger HighCPUUsage and CriticalCPUUsage
bash remediation/scripts/simulate_cpu_spike.sh 300

# Trigger DiskSpaceCritical (and auto-remediation)
bash remediation/scripts/simulate_disk_full.sh

# Trigger InstanceDown
bash remediation/scripts/simulate_service_down.sh node-exporter

# Trigger HighMemoryUsage
bash remediation/scripts/simulate_memory_pressure.sh
```

### Checking Alert State

```bash
# View currently firing alerts in Prometheus
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool

# View alerts received by Alertmanager
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool

# View alert groups in Alertmanager
curl -s http://localhost:9093/api/v2/alerts/groups | python3 -m json.tool
```
