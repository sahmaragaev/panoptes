# PANOPTES Demo Script

Step-by-step presentation guide for demonstrating the Unified Monitoring & Alerting System. This script covers the full demo flow, talking points, contingency plans, and Q&A preparation.

**Estimated demo duration**: 20-25 minutes

---

## Table of Contents

1. [Pre-Demo Checklist](#pre-demo-checklist)
2. [Opening: Architecture Overview](#opening-architecture-overview)
3. [Demo Flow](#demo-flow)
   - [Step 1: Infrastructure Overview Dashboard](#step-1-infrastructure-overview-dashboard)
   - [Step 2: Node Detail Dashboard](#step-2-node-detail-dashboard)
   - [Step 3: Trigger a CPU Spike](#step-3-trigger-a-cpu-spike)
   - [Step 4: Show the Alerting Flow](#step-4-show-the-alerting-flow)
   - [Step 5: Trigger a Service Down Event](#step-5-trigger-a-service-down-event)
   - [Step 6: Show Auto-Remediation](#step-6-show-auto-remediation)
   - [Step 7: Loki Log Explorer](#step-7-loki-log-explorer)
   - [Step 8: Active Directory Dashboard](#step-8-active-directory-dashboard)
   - [Step 9: Connect a Remote Agent (SaaS Mode)](#step-9-connect-a-remote-agent-saas-mode)
   - [Step 10: System Health Dashboard](#step-10-system-health-dashboard)
4. [Cleanup Commands](#cleanup-commands)
5. [Backup Plan](#backup-plan)
6. [Q&A Preparation](#qa-preparation)

---

## Pre-Demo Checklist

Complete these steps **at least 30 minutes before** the demo begins.

### Environment Verification

- [ ] All containers are running: `docker compose ps` (all services for your chosen profile should show `Up`)
- [ ] Prometheus targets are all UP: Open http://localhost:9090/targets
- [ ] Grafana is accessible: Open http://localhost:3000 and log in (admin / panoptes2026)
- [ ] Alertmanager is accessible: Open http://localhost:9093
- [ ] Webhook receiver is healthy: `curl http://localhost:5001/health`
- [ ] No alerts are currently firing: Check http://localhost:9090/alerts

### Data Verification

- [ ] Prometheus has at least 15 minutes of data: Check any dashboard for data presence
- [ ] Loki is receiving logs: Check the Loki Logs dashboard for recent entries
- [ ] Custom exporter metrics are available: Run `curl http://localhost:9101/metrics | head -20`

### Browser Tabs (pre-open in order)

1. Architecture diagram (slide or `docs/architecture.md` rendered)
2. Grafana - Infrastructure Overview dashboard
3. Grafana - Node Detail dashboard
4. Grafana - Loki Logs dashboard
5. Grafana - PANOPTES Custom Metrics dashboard
6. Prometheus Targets page (http://localhost:9090/targets)
7. Alertmanager UI (http://localhost:9093)
8. Telegram group -- visible on screen or second monitor

### Terminal Windows

- [ ] Terminal 1: Ready for running simulation scripts (in the `panoptes/` project directory)
- [ ] Terminal 2: Tailing Alertmanager logs: `docker compose logs -f alertmanager`
- [ ] Terminal 3: Tailing webhook receiver logs: `docker compose logs -f webhook-receiver`

### Notification Channels

- [ ] Telegram bot is configured and tested: Send a test message
- [ ] Keep Telegram visible during the demo to show notifications arriving in real time

---

## Opening: Architecture Overview

**Duration**: 2-3 minutes

### Talking Points

> "PANOPTES, the Unified Monitoring and Alerting System, is designed for the CeDAR infrastructure at ADA University. It brings together multiple open-source monitoring tools into a single platform."

Show the architecture diagram (from `docs/architecture.md` or a prepared slide) and walk through:

1. **Data Collection Layer**: "We use Node Exporter for host metrics, cAdvisor for container metrics, Promtail for log shipping, and our custom Python exporter for application-level checks like HTTP health, certificate expiry, and Active Directory monitoring."

2. **Storage Layer**: "Prometheus stores time-series metrics with a 15-second scrape interval and 15-day retention. Loki stores logs with label-based indexing, which is far more efficient than full-text indexing."

3. **Alerting Layer**: "Prometheus evaluates 26 alert rules every 15 seconds. When an alert fires, Alertmanager routes it based on severity -- warnings and critical alerts go to Telegram. Alerts with a remediation label are also sent to our webhook receiver."

4. **Remediation Layer**: "The webhook receiver triggers Ansible playbooks to automatically fix known issues -- disk cleanup, memory clearing, service restarts -- without human intervention."

5. **Visualization Layer**: "Everything comes together in Grafana with 8 pre-built dashboards. Let me show you."

---

## Demo Flow

---

### Step 1: Infrastructure Overview Dashboard

**Duration**: 3-4 minutes

**Action**: Switch to the Grafana tab showing the Infrastructure Overview dashboard.

#### What to Show

- **Overall health panel**: Point out the number of monitored targets and their UP/DOWN status
- **CPU usage gauge/graph**: "This shows real-time CPU usage across all monitored hosts, scraped every 15 seconds"
- **Memory usage panel**: "Memory utilization including buffers and cache"
- **Disk usage panel**: "Disk space usage per filesystem, filtered to exclude temporary filesystems"
- **Network I/O panel**: "Inbound and outbound network traffic"
- **Alert status panel**: "Current alert state -- green means all clear"

#### Talking Points

> "This is the primary operations dashboard. At a glance, you can see the health of the entire infrastructure. Every panel is backed by PromQL queries against Prometheus data."

> "The dashboard auto-refreshes every 15 seconds, matching our scrape interval, so what you see is always within 30 seconds of the current state."

> "All dashboards are provisioned as code -- they are JSON files in our repository, automatically loaded when Grafana starts. No manual configuration is needed."

---

### Step 2: Node Detail Dashboard

**Duration**: 2-3 minutes

**Action**: Switch to the Node Detail dashboard. Select the PANOPTES VPS host from the dropdown.

#### What to Show

- **Host selector dropdown**: Show how you can switch between monitored hosts
- **CPU per-core breakdown**: "Each CPU core's usage is visible individually"
- **Memory breakdown**: "This shows used, buffered, cached, and free memory"
- **Disk I/O**: "Read and write throughput per disk"
- **Network per-interface**: "Traffic per network interface with error counters"
- **System load**: "1, 5, and 15-minute load averages overlaid with the CPU count line"
- **Filesystem usage**: "Per-mount-point disk usage with predictive fill time"

#### Talking Points

> "When the Infrastructure Overview shows a problem, you drill down into this Node Detail dashboard to investigate a specific host. This is the second layer of observability."

> "Notice the memory panel -- it uses node_memory_MemAvailable, not just MemFree, because MemAvailable accounts for reclaimable buffers and cache. This gives a more accurate picture of actual memory pressure."

---

### Step 3: Trigger a CPU Spike

**Duration**: 3-4 minutes

**Action**: Switch to Terminal 1 and run the CPU simulation.

```bash
bash remediation/scripts/simulate_cpu_spike.sh 120
```

#### What to Show

1. **Terminal**: Show the command running and explain what `stress-ng` does
2. **Grafana Node Detail**: Switch to the dashboard and watch CPU graphs climb in real time
3. **Prometheus Alerts page**: Open http://localhost:9090/alerts and wait for `HighCPUUsage` to go to PENDING, then FIRING (after 5 minutes of sustained load, or explain the "for" duration)

#### Talking Points

> "I am using stress-ng to generate a CPU spike on all cores. This simulates a runaway process or an unexpected batch job."

> "Watch the Grafana dashboard -- within 15 seconds, you will see the CPU graph respond. Prometheus scrapes metrics every 15 seconds, so the visualization is near-real-time."

> "After 5 minutes of sustained CPU usage above 85%, Prometheus will transition the HighCPUUsage alert from PENDING to FIRING and send it to Alertmanager."

**Note**: If the demo is time-constrained, you can skip waiting for the full 5-minute "for" duration and explain the mechanism verbally. Alternatively, pre-trigger the spike 5 minutes before the demo.

#### After Showing

Kill the stress test:

```bash
pkill stress-ng
```

---

### Step 4: Show the Alerting Flow

**Duration**: 3-4 minutes

**Action**: Show the alert flowing from Prometheus to Alertmanager to Telegram.

#### What to Show

1. **Prometheus Alerts page** (http://localhost:9090/alerts):
   - Show the alert rule definition
   - Show the FIRING state with current value
   - Explain the `for` duration mechanism

2. **Alertmanager UI** (http://localhost:9093):
   - Show the received alert with labels and annotations
   - Show the grouping (by alertname, severity, instance)
   - Show the "Silence" button and explain when you would use it

3. **Telegram**:
   - Show the notification that arrived
   - Point out the alert name, summary, description, and current value
   - Show the resolved notification after killing stress-ng

#### Talking Points

> "Here is the full alerting pipeline in action. Prometheus detected the anomaly, waited for the configured 'for' duration to avoid false positives, then fired the alert to Alertmanager."

> "Alertmanager groups alerts by name, severity, and instance. This means if 10 CPU-related alerts fire at the same time, the team gets one consolidated notification, not 10 separate messages."

> "We have inhibition rules configured. For example, if an InstanceDown alert fires, all other alerts for that same instance are automatically suppressed. This prevents notification storms when a host goes offline."

> "Notice the 'send_resolved: true' -- when the condition clears, the team gets a green 'RESOLVED' notification so they know the issue has passed."

---

### Step 5: Trigger a Service Down Event

**Duration**: 2-3 minutes

**Action**: Stop the Node Exporter to trigger InstanceDown.

```bash
bash remediation/scripts/simulate_service_down.sh node-exporter
```

#### What to Show

1. **Prometheus Targets page**: Refresh and show node-exporter target turning red (DOWN)
2. **Prometheus Alerts page**: Show InstanceDown going to PENDING, then FIRING (after 1 minute)
3. **Grafana Infrastructure Overview**: Show the gap in metrics for the downed host
4. **Telegram**: Show the critical alert notification

#### Talking Points

> "I have stopped the Node Exporter container, simulating a host or exporter failure. Within 15 seconds, Prometheus detects the scrape failure."

> "After 1 minute, the InstanceDown alert fires. This is a critical alert, so it goes to Telegram, reaching the team immediately."

> "Notice in Grafana -- the metrics for this host now show a gap. This is the visual indicator that data collection has stopped."

> "The inhibition rule also kicks in: any other alerts that were active for this instance, such as HighCPUUsage, are automatically suppressed since the root cause is that the instance is down."

#### Restore

```bash
docker start node-exporter
```

> "After restarting the exporter, Prometheus detects it within 15 seconds, the alert resolves, and the team gets a RESOLVED notification."

---

### Step 6: Show Auto-Remediation

**Duration**: 3-4 minutes

**Action**: Demonstrate the auto-remediation pipeline. This is a key differentiating feature.

#### Option A: Simulate Disk Alert (Full Demo)

```bash
# This creates a 5GB file to trigger disk usage alert
bash remediation/scripts/simulate_disk_full.sh
```

Then explain the flow while watching Terminal 3 (webhook receiver logs).

#### Option B: Walkthrough with API (Faster)

Manually send a test alert to the webhook receiver:

```bash
curl -X POST http://localhost:5001/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [{
      "status": "firing",
      "labels": {
        "alertname": "DiskSpaceCritical",
        "severity": "critical",
        "remediation": "disk_cleanup",
        "instance": "localhost:9100"
      },
      "annotations": {
        "summary": "Critical disk space on localhost",
        "description": "Disk usage above 90%"
      }
    }]
  }'
```

#### What to Show

1. **Terminal 3 (webhook receiver logs)**: Show the incoming alert, the remediation label extraction, and the Ansible playbook execution
2. **Webhook receiver history**: `curl http://localhost:5001/history | python3 -m json.tool`
3. **Webhook receiver cooldowns**: `curl http://localhost:5001/cooldowns | python3 -m json.tool`

#### Talking Points

> "This is where PANOPTES goes beyond traditional monitoring. When an alert fires with a 'remediation' label, Alertmanager routes it to our webhook receiver in addition to the normal notification channels."

> "The webhook receiver extracts the remediation type and target host from the alert payload, then maps it to an Ansible playbook. In this case, DiskSpaceCritical triggers the disk_cleanup playbook."

> "The disk_cleanup playbook runs Docker system prune, truncates large log files, vacuums systemd journals, and runs apt autoclean -- all automatically, without human intervention."

> "We have a 30-minute cooldown per host-action pair. This prevents remediation loops where the same action fires repeatedly. You can see the active cooldowns via the API."

> "Currently, we support 5 remediation actions: disk cleanup, memory clearing, service restart, log rotation, and Docker cleanup. New actions can be added by writing an Ansible playbook and adding it to the playbook map."

#### Cleanup (if using Option A)

```bash
rm /tmp/panoptes_disk_test
```

---

### Step 7: Loki Log Explorer

**Duration**: 2-3 minutes

**Action**: Switch to the Grafana Loki Logs dashboard or open Grafana Explore.

#### What to Show

1. **Loki Logs Dashboard**: Show pre-built panels for system logs, auth logs, and Docker container logs
2. **Grafana Explore** (left sidebar > Explore):
   - Select Loki as the data source
   - Run a query for auth logs:
     ```
     {job="auth"} |= "sshd"
     ```
   - Run a query for Docker container logs:
     ```
     {compose_service="prometheus"}
     ```
   - Show log volume histogram and log lines

3. **Label filtering**: Show how to filter by `job`, `container`, `unit`, etc.

#### Talking Points

> "PANOPTES does not just collect metrics -- it also aggregates logs. Promtail ships logs from four sources: system logs, auth logs, Docker container logs via Docker service discovery, and systemd journal entries."

> "Loki uses label-based indexing rather than full-text indexing. This means it is significantly more resource-efficient than Elasticsearch. You query by labels first, then filter the content."

> "Here I am searching for SSH-related auth log entries. In a security context, you could use this to investigate unauthorized access attempts, see which IPs are trying to connect, and correlate with metrics."

> "The Docker service discovery is automatic -- when a new container starts, Promtail discovers it and begins collecting its logs without any configuration change."

---

### Step 8: Active Directory Dashboard

**Duration**: 2 minutes

**Action**: Switch to the PANOPTES Custom Metrics dashboard (or a dedicated AD dashboard if available).

#### What to Show

- **HTTP Health panels**: Show the health status of Grafana, Prometheus, Alertmanager, and Loki as reported by the custom exporter
- **Certificate Expiry panels**: Show TLS certificate expiry monitoring
- **AD Health section** (explain even if not connected to live AD):
  - LDAP connectivity to domain controllers
  - Replication health

#### Talking Points

> "Our custom Python exporter fills gaps that off-the-shelf exporters cannot cover. It checks HTTP health endpoints, monitors TLS certificate expiration, and can connect to Active Directory domain controllers."

> "The AD health module connects to domain controllers via LDAP on port 636 and checks connectivity and replication status. In the CeDAR environment, this monitors the university's Active Directory infrastructure."

> "Since the AD module requires access to actual domain controllers, it is disabled in this demo environment. But the architecture is in place -- you enable it by setting 'enabled: true' in the exporter config and providing the domain controller addresses."

> "Certificate expiry monitoring alerts the team before TLS certificates expire, preventing those dreaded 'certificate expired' outages that catch everyone by surprise."

---

### Step 9: Connect a Remote Agent (SaaS Mode)

**Duration**: 3-4 minutes

**Action**: Demonstrate connecting a remote host using the Grafana Alloy agent.

#### What to Show

1. **Generate an API key on the server:**
   ```bash
   bash scripts/generate-api-key.sh --tenant demo-host
   ```

2. **Install the agent on a remote host** (or a second terminal simulating a remote host):
   ```bash
   curl -sSL https://raw.githubusercontent.com/ada-university/panoptes/main/agent/install.sh | bash -s -- \
     --server https://panoptes.example.com:8080 \
     --key pnpt_demo-host_xxxxxxxxxxxx \
     --tenant demo-host
   ```

3. **Show the remote host appearing in Prometheus targets** within 30 seconds
4. **Show the remote host's metrics in Grafana** with the tenant label

#### Talking Points

> "This is our SaaS mode. With a single command, we can onboard a remote host -- even one behind NAT or a firewall. The Grafana Alloy agent pushes metrics and logs to our nginx gateway, which authenticates the request using a per-tenant API key."

> "The key thing here is that we do not need inbound connectivity to the remote host. The agent initiates the connection outbound, which works through firewalls and NAT. This is how we can monitor branch offices, customer servers, or cloud VMs from a single central dashboard."

> "Each tenant gets a unique API key, and all their metrics are tagged with a tenant label. This means we can filter dashboards by tenant and enforce access control in Grafana."

---

### Step 10: System Health Dashboard

**Duration**: 2 minutes

**Action**: Show the Alertmanager Overview dashboard or a self-monitoring panel.

#### What to Show

- **Monitoring stack self-monitoring**: Prometheus scraping itself, Alertmanager, Grafana, Loki
- **Alert rule evaluation**: Show the rule evaluation latency and duration
- **Notification success/failure rates**: Alertmanager notification metrics
- **Prometheus memory and TSDB stats**: How much data is stored, cardinality

#### Talking Points

> "A monitoring system that cannot monitor itself is a liability. PANOPTES has 5 dedicated alert rules for self-monitoring."

> "PrometheusTargetDown fires if any core monitoring component goes down. AlertmanagerNotificationFailed fires if alert delivery fails. These are our 'meta-alerts' -- they watch the watchers."

> "Prometheus memory usage is tracked against its 512 MB limit. If it approaches the limit, we get a warning before an OOM kill takes down our monitoring."

> "Loki ingestion rate is monitored as well. If it drops to zero, we know the log pipeline is broken."

---

## Cleanup Commands

Run these after the demo to restore the environment to a clean state.

```bash
# Kill any running stress tests
pkill stress-ng 2>/dev/null

# Restart any stopped containers
docker start node-exporter 2>/dev/null

# Remove the disk test file
rm -f /tmp/panoptes_disk_test

# Wait for alerts to resolve (or manually check)
curl -s http://localhost:9090/api/v1/alerts | python3 -c "
import sys, json
data = json.load(sys.stdin)
firing = [a for a in data['data']['alerts'] if a['state'] == 'firing']
print(f'{len(firing)} alerts still firing')
for a in firing:
    print(f'  - {a[\"labels\"][\"alertname\"]}')
"

# Verify all containers are running
docker compose ps
```

---

## Backup Plan

### If a Container Fails to Start

```bash
# Quick restart
docker compose restart <service>

# Full rebuild
docker compose up -d --build <service>

# Nuclear option (WARNING: loses data)
docker compose down -v && docker compose up -d
```

### If Grafana Dashboards Are Empty

- Check that the time range is set to "Last 15 minutes" or "Last 1 hour" (top-right dropdown)
- Verify the data source is connected: Connections > Data Sources > Test
- If still empty, demonstrate Prometheus directly: http://localhost:9090/graph and run `up` query

### If Telegram Notifications Do Not Arrive

- Show the Alertmanager UI instead (http://localhost:9093) -- alerts are visible there even if notifications fail
- Check Alertmanager logs for errors: `docker compose logs alertmanager | tail -20`
- Explain that the notification channel is configured but there may be a network/credential issue
- Use the Alertmanager UI to show the alert was received and routed correctly

### If the CPU Spike Does Not Trigger an Alert

- The `for: 5m` duration means you need to wait 5 minutes. If time is short, explain the mechanism verbally
- Alternatively, pre-trigger the spike before the demo and have it already in FIRING state
- You can also demonstrate with a lower threshold: "In production, we have this set to 85%. For this demo, imagine we set it to 10% -- the same mechanism applies."

### If Auto-Remediation Does Not Work

- Use the manual API call (Option B in Step 6) to directly trigger the webhook receiver
- Show the webhook receiver history endpoint to demonstrate the feature even without live Ansible execution
- Explain that Ansible requires SSH access to the target host, which may not be configured in the demo environment

### If the Network Is Slow or Unreliable

- All dashboards are pre-provisioned locally -- they do not require internet access
- Prometheus, Grafana, and Loki all run locally
- Only Telegram notifications require internet -- fall back to showing Alertmanager UI

---

## Q&A Preparation

### Common Questions and Suggested Answers

**Q: Why Prometheus instead of other monitoring tools like Datadog or New Relic?**

> "Prometheus is open-source and self-hosted, which means no vendor lock-in and no per-host licensing costs. For a university infrastructure, this is significant. It is also the de facto standard for cloud-native monitoring, with native Kubernetes integration and a massive ecosystem of exporters. The pull-based model simplifies firewall configuration -- we do not need to open inbound ports on monitored hosts."

**Q: How does SaaS mode work for remote hosts?**

> "PANOPTES includes a SaaS mode where remote hosts run a lightweight Grafana Alloy agent that pushes metrics and logs to our central server through an nginx gateway. Each tenant gets a unique API key for authentication. This means we can monitor hosts behind NAT or firewalls without requiring inbound connectivity. During the demo, I can show you how to connect a remote host in under a minute."

**Q: How does this scale to hundreds of hosts?**

> "For up to 50-100 hosts, the current single-instance deployment handles it well. Beyond that, we would use Prometheus federation -- each cluster runs its own Prometheus, and a central federation Prometheus aggregates key metrics. Loki supports a microservices deployment mode for high-volume log environments. The architecture document covers our scaling strategy in detail."

**Q: What happens if Prometheus itself goes down?**

> "We have self-monitoring alerts (PrometheusTargetDown) that would fire before a complete outage. If Prometheus does go down, Alertmanager retains its state and will continue delivering any already-fired alerts. Our recommended HA strategy is to run two identical Prometheus instances -- both scrape the same targets, and Alertmanager deduplicates alerts from both."

**Q: How secure is this system?**

> "All containers run with memory limits and read-only configuration mounts. Secrets are stored in environment variables, not in configuration files. In the Kubernetes deployment, secrets are Kubernetes Secrets, and the namespace is isolated. All external-facing services are behind TLS via Traefik. Grafana has sign-up disabled and uses strong admin credentials. The firewall allows only necessary ports."

**Q: What is the cost of running this?**

> "The entire stack runs on a single VPS with 4 vCPUs, 8 GB RAM, and 80 GB SSD. At current cloud pricing, that is approximately $20-40 per month. All software is open-source with no licensing costs. Compare that to commercial monitoring solutions which charge per host per month."

**Q: Can it monitor cloud services like AWS or Azure?**

> "Yes, through Prometheus exporters. There are official exporters for AWS CloudWatch, Azure Monitor, and GCP. You would add them as scrape targets in the Prometheus configuration. Grafana also has native data source plugins for CloudWatch and Azure Monitor."

**Q: How do you add new alert rules?**

> "Alert rules are defined in YAML in the configs/prometheus/alert_rules.yml file. You add a new rule with a PromQL expression, a severity label, and annotations. Then you validate with promtool and reload Prometheus. The entire process takes a few minutes and does not require a restart."

**Q: What if the auto-remediation makes things worse?**

> "We have multiple safeguards. First, the 30-minute cooldown prevents the same action from running repeatedly. Second, all Ansible playbooks use 'ignore_errors: yes' for non-critical tasks, so a failed sub-task does not cascade. Third, the remediation history is logged and queryable via API, so we can audit what happened. Fourth, remediation only triggers for alerts with an explicit 'remediation' label -- it is opt-in per alert rule."

**Q: How is this different from a student project? Is this production-ready?**

> "The architecture follows industry best practices used at companies like GitLab and Cloudflare. The Prometheus + Grafana + Alertmanager stack is the same foundation used in production at thousands of companies. Our additions -- the custom exporter, webhook receiver, and Ansible remediation -- follow the same patterns. The deployment is containerized, configuration is version-controlled, and the system includes self-monitoring. For the CeDAR infrastructure scale, this is production-ready."
