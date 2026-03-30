# PANOPTES Setup Guide

Complete guide for deploying the Unified Monitoring & Alerting System from scratch on a VPS or local development environment.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Domain and DNS Setup](#domain-and-dns-setup)
3. [VPS Provisioning](#vps-provisioning)
4. [Docker Compose Deployment](#docker-compose-deployment)
5. [K3s Kubernetes Deployment](#k3s-kubernetes-deployment)
6. [Configuring Environment Variables](#configuring-environment-variables)
7. [Adding Monitored Targets](#adding-monitored-targets)
8. [Configuring Notification Channels](#configuring-notification-channels)
9. [TLS Certificate Setup](#tls-certificate-setup)
10. [Verifying the Deployment](#verifying-the-deployment)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Hardware Requirements

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 2 vCPUs | 4 vCPUs |
| RAM | 4 GB | 8 GB |
| Disk | 40 GB SSD | 80 GB SSD |
| Network | 100 Mbps | 1 Gbps |

### Software Requirements

| Software | Version | Purpose |
|---|---|---|
| Ubuntu | 22.04+ (LTS) | Operating system |
| Docker CE | 24.0+ | Container runtime |
| Docker Compose | v2.20+ (plugin) | Multi-container orchestration |
| K3s | v1.28+ | Lightweight Kubernetes (production) |
| Git | 2.30+ | Repository management |
| kubectl | v1.28+ | Kubernetes CLI (for K3s deployment) |

### Optional Tools

| Tool | Purpose |
|---|---|
| `promtool` | Validate Prometheus configuration and alert rules |
| `yamllint` | Validate YAML files |
| `ruff` | Python linter for custom exporter code |
| `stress-ng` | Generate CPU/memory load for demo simulations |
| `ansible` | Required on the host if running remediation playbooks |

---

## Domain and DNS Setup

If deploying with public-facing dashboards, configure DNS A records pointing to your VPS IP address.

### Required DNS Records

| Subdomain | Record Type | Value | Purpose |
|---|---|---|---|
| `grafana.panoptes.example.com` | A | `<VPS_IP>` | Grafana dashboards |
| `prometheus.panoptes.example.com` | A | `<VPS_IP>` | Prometheus UI and API |
| `alertmanager.panoptes.example.com` | A | `<VPS_IP>` | Alertmanager UI |

Replace `panoptes.example.com` with your actual domain. Update the `DOMAIN` variable in `.env` accordingly.

### DNS Propagation

After creating records, verify propagation:

```bash
dig +short grafana.panoptes.example.com
dig +short prometheus.panoptes.example.com
```

DNS propagation typically takes 5-30 minutes depending on the provider.

---

## VPS Provisioning

The `scripts/setup-vps.sh` script automates the initial server configuration.

### Automated Setup

```bash
# SSH into your VPS
ssh root@<VPS_IP>

# Clone the repository
git clone https://github.com/ada-university/panoptes.git /opt/monitoring/panoptes
cd /opt/monitoring/panoptes

# Run the provisioning script (must be root)
bash scripts/setup-vps.sh
```

This script performs the following:

1. Updates system packages (`apt update && apt upgrade`)
2. Installs Docker CE and Docker Compose plugin
3. Installs K3s (lightweight Kubernetes)
4. Configures UFW firewall (allows ports 22, 80, 443, 6443, 10250)
5. Installs `stress-ng` for demo simulations
6. Installs `promtool` for alert rule validation
7. Configures Docker daemon (JSON log driver with size limits)
8. Creates `/opt/monitoring` directory

### Manual Setup (if preferred)

If you prefer manual installation, ensure the following are installed:

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker

# Install Docker Compose plugin
apt install -y docker-compose-plugin

# Install K3s (optional, for Kubernetes deployment)
curl -sfL https://get.k3s.io | sh -

# Verify installations
docker --version
docker compose version
kubectl version --client
```

---

## Docker Compose Deployment

This is the simplest deployment method, suitable for single-server setups and development.

### Step 1: Clone the Repository

```bash
git clone https://github.com/ada-university/panoptes.git
cd panoptes
```

### Step 2: Create Environment File

```bash
cp .env.example .env
```

Edit `.env` with your actual credentials (see [Configuring Environment Variables](#configuring-environment-variables)).

### Step 3: Deploy

**Option A: Using Make**

```bash
make up
```

**Option B: Using the deployment script**

```bash
bash scripts/deploy-docker.sh
```

The deployment script will:
- Check for `.env` (copies from `.env.example` if missing)
- Build custom Docker images (custom-exporter, webhook-receiver)
- Start all 12 services
- Wait for containers to become healthy (up to 120 seconds)
- Display access URLs and default credentials

**Option C: Manual Docker Compose**

```bash
docker compose build custom-exporter webhook-receiver
docker compose up -d
```

### Step 4: Verify

```bash
docker compose ps
```

All core containers should show `Up` status (the exact count depends on the profile used):

```
NAME               STATUS
prometheus         Up
node-exporter      Up
alertmanager       Up
grafana            Up
cadvisor           Up
custom-exporter    Up
webhook-receiver   Up
```

With the `logging` profile, you will also see `loki` and `promtail`. With the `full` profile, `snmp-exporter` is added. With the `saas` profile, `nginx-gateway` is added.

### Access URLs (Docker Compose)

| Service | URL | Default Credentials |
|---|---|---|
| Grafana | http://localhost:3000 | admin / panoptes2026 |
| Prometheus | http://localhost:9090 | N/A |
| Alertmanager | http://localhost:9093 | N/A |
| Loki | http://localhost:3100 | N/A |
| cAdvisor | http://localhost:8080 | N/A |
| snmp_exporter | http://localhost:9116 | N/A |
| nginx Gateway | http://localhost:8080 | N/A (API key auth) |
| Custom Exporter | http://localhost:9101 | N/A |
| Webhook Receiver | http://localhost:5001/health | N/A |

### Development Mode

For development with debug logging and extra ports:

```bash
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
```

This enables:
- Debug log levels for Prometheus, Grafana, and webhook-receiver
- Additional mapped ports (9091, 3001, 3101, 9094) for testing

---

## K3s Kubernetes Deployment

Production deployment using K3s (lightweight Kubernetes).

### Step 1: Ensure K3s Is Running

```bash
# Check K3s status
systemctl status k3s

# Verify kubectl access
kubectl get nodes
```

If K3s is not installed, run:

```bash
curl -sfL https://get.k3s.io | sh -
```

### Step 2: Create Environment File

```bash
cd /opt/monitoring/panoptes
cp .env.example .env
# Edit .env with your actual credentials
```

### Step 3: Deploy

**Option A: Using the deployment script**

```bash
bash scripts/deploy-k8s.sh
```

This script will:
1. Verify `kubectl` is available
2. Create the `panoptes` namespace
3. Create a Kubernetes Secret from `.env`
4. Apply all manifests (PVCs, ConfigMaps, Deployments, Services, DaemonSets, Ingress)
5. Wait for all pods to become ready (timeout: 300s)
6. Display pod status and service URLs

**Option B: Using Make**

```bash
make deploy-k8s
```

**Option C: Manual kubectl**

```bash
# Create namespace
kubectl apply -f k8s/namespace.yml

# Create secret from .env
kubectl create secret generic panoptes-secrets \
    --from-env-file=.env \
    -n panoptes

# Apply all component manifests
kubectl apply -f k8s/prometheus/ -n panoptes
kubectl apply -f k8s/alertmanager/ -n panoptes
kubectl apply -f k8s/grafana/ -n panoptes
kubectl apply -f k8s/custom-exporter/ -n panoptes
kubectl apply -f k8s/webhook-receiver/ -n panoptes
kubectl apply -f k8s/cadvisor/ -n panoptes
kubectl apply -f k8s/snmp-exporter/ -n panoptes
kubectl apply -f k8s/nginx/ -n panoptes
kubectl apply -f k8s/ingress/ -n panoptes
```

### Step 4: Verify

```bash
kubectl get pods -n panoptes
kubectl get svc -n panoptes
kubectl get ingress -n panoptes
```

All pods should show `Running` status with `1/1` ready containers.

### Access URLs (K3s)

With Ingress configured:

| Service | URL |
|---|---|
| Grafana | https://grafana.panoptes.example.com |
| Prometheus | https://prometheus.panoptes.example.com |
| Alertmanager | https://alertmanager.panoptes.example.com |

Without Ingress (NodePort):

```bash
# Get the node IP
kubectl get nodes -o wide

# Access via NodePort
http://<NODE_IP>:3000   # Grafana
http://<NODE_IP>:9090   # Prometheus
```

---

## Configuring Environment Variables

The `.env` file controls all sensitive configuration values. Each variable is explained below.

### Grafana

| Variable | Default | Description |
|---|---|---|
| `GRAFANA_ADMIN_USER` | `admin` | Grafana administrator username |
| `GRAFANA_ADMIN_PASSWORD` | `panoptes2026` | Grafana administrator password. **Change this in production.** |

### Telegram Notifications

| Variable | Default | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `YOUR_BOT_TOKEN` | Bot token from @BotFather. See [Telegram setup](#telegram-bot-setup). |
| `TELEGRAM_CHAT_ID` | `-1001234567890` | Chat or group ID where alerts are sent. Negative numbers indicate groups. |

### Email / SMTP

| Variable | Default | Description |
|---|---|---|
| `SMTP_HOST` | `smtp.gmail.com` | SMTP server hostname |
| `SMTP_PORT` | `587` | SMTP server port (587 for STARTTLS, 465 for SSL) |
| `SMTP_USER` | `alerts@example.com` | SMTP authentication username (often the email address) |
| `SMTP_PASSWORD` | `app_password` | SMTP authentication password. For Gmail, use an [App Password](https://myaccount.google.com/apppasswords). |

### Domain

| Variable | Default | Description |
|---|---|---|
| `DOMAIN` | `panoptes.example.com` | Base domain for Ingress routing. Subdomains (grafana, prometheus, alertmanager) are configured in the Ingress manifest. |

---

## Adding Monitored Targets

### Adding a Linux Host

1. Install Node Exporter on the target host:

```bash
# On the target host
wget https://github.com/prometheus/node_exporter/releases/download/v1.9.0/node_exporter-1.9.0.linux-amd64.tar.gz
tar xzf node_exporter-1.9.0.linux-amd64.tar.gz
sudo cp node_exporter-1.9.0.linux-amd64/node_exporter /usr/local/bin/

# Create a systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo useradd -rs /bin/false node_exporter
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

2. Add the target to Prometheus scrape configuration (`configs/prometheus/prometheus.yml`):

```yaml
scrape_configs:
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          hostname: 'panoptes-vps'
      - targets: ['192.168.1.10:9100']     # <-- Add new target here
        labels:
          hostname: 'web-server-01'
```

3. Reload Prometheus:

```bash
# Docker Compose
docker compose exec prometheus kill -HUP 1

# Or via the lifecycle API
curl -X POST http://localhost:9090/-/reload
```

### Adding a Docker Host

1. Deploy cAdvisor on the target Docker host (as shown in `docker-compose.yml`).

2. Add the target to the `cadvisor` scrape job in `configs/prometheus/prometheus.yml`:

```yaml
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080', '192.168.1.10:8080']
```

3. Reload Prometheus configuration.

### Adding a Windows Host

1. Install the Windows Exporter on the target host:
   - Download from the [windows_exporter releases page](https://github.com/prometheus-community/windows_exporter/releases)
   - Install as a Windows service pointing to the default port 9182
   - For Active Directory monitoring, enable the `ad` collector: `windows_exporter --collectors.enabled="cpu,cs,logical_disk,memory,net,os,service,ad"`

2. Add the target to the `windows-exporter` scrape job in `configs/prometheus/prometheus.yml`:

```yaml
  - job_name: 'windows-exporter'
    static_configs:
      - targets: ['192.168.1.20:9182']
        labels:
          hostname: 'ad-server-01'
```

3. Reload Prometheus and verify the target appears in http://localhost:9090/targets.

---

## Configuring Notification Channels

### Telegram Bot Setup

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` and follow the prompts to create a bot
3. Copy the bot token (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)
4. Create a group or channel for alerts and add the bot as a member
5. Get the chat ID:

```bash
# Send a test message to your group, then:
curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates" | python3 -m json.tool
# Look for "chat": {"id": -1001234567890, ...}
```

6. Update your `.env` file:

```
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_CHAT_ID=-1001234567890
```

### SMTP / Email Setup

For Gmail:

1. Enable 2-Factor Authentication on your Google account
2. Generate an App Password at [https://myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
3. Update your `.env` file:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-alerts-account@gmail.com
SMTP_PASSWORD=xxxx-xxxx-xxxx-xxxx
```

For other SMTP providers:

| Provider | SMTP Host | Port |
|---|---|---|
| Gmail | smtp.gmail.com | 587 |
| Outlook | smtp.office365.com | 587 |
| SendGrid | smtp.sendgrid.net | 587 |
| Mailgun | smtp.mailgun.org | 587 |

---

## TLS Certificate Setup

### Automatic (Let's Encrypt via Traefik)

K3s includes Traefik as the default Ingress controller. To enable automatic TLS:

1. Ensure your DNS records are pointing to the VPS IP (see [Domain and DNS Setup](#domain-and-dns-setup))

2. Create a Traefik TLS configuration:

```yaml
# k8s/traefik/tlsstore.yml
apiVersion: traefik.io/v1alpha1
kind: TLSStore
metadata:
  name: default
  namespace: panoptes
spec:
  defaultCertificate:
    secretName: panoptes-tls
```

3. Create a certificate resolver (for automatic Let's Encrypt):

```bash
# Edit the Traefik Helm values (K3s uses HelmChartConfig)
kubectl apply -f - <<EOF
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    certResolvers:
      letsencrypt:
        email: admin@example.com
        storage: /data/acme.json
        httpChallenge:
          entryPoint: web
EOF
```

4. Update the Ingress annotation:

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
```

### Manual Certificate

If you have existing certificates:

```bash
# Create TLS secret from certificate files
kubectl create secret tls panoptes-tls \
    --cert=fullchain.pem \
    --key=privkey.pem \
    -n panoptes
```

The Ingress manifest (`k8s/ingress/ingress.yml`) already references `panoptes-tls` as the TLS secret.

---

## Verifying the Deployment

After deployment, verify each service is healthy.

### Health Check Commands

```bash
# Prometheus
curl -f http://localhost:9090/-/healthy
# Expected: Prometheus Server is Healthy.

# Alertmanager
curl -f http://localhost:9093/-/healthy
# Expected: OK

# Grafana
curl -f http://localhost:3000/api/health
# Expected: {"commit":"...","database":"ok","version":"11.5.2"}

# Loki
curl -f http://localhost:3100/ready
# Expected: ready

# Custom Exporter
curl -f http://localhost:9101/metrics | head -5
# Expected: Prometheus-format metrics output

# Webhook Receiver
curl -f http://localhost:5001/health
# Expected: {"status":"healthy"}

# Node Exporter
curl -f http://localhost:9100/metrics | head -5
# Expected: Prometheus-format metrics output

# cAdvisor
curl -f http://localhost:8080/healthz
# Expected: ok

```

### Prometheus Targets

Open http://localhost:9090/targets and verify all scrape targets show **UP** status:

- `prometheus` (localhost:9090)
- `node-exporter` (node-exporter:9100)
- `alertmanager` (alertmanager:9093)
- `grafana` (grafana:3000)
- `loki` (loki:3100)
- `cadvisor` (cadvisor:8080)
- `custom-exporter` (custom-exporter:9101)

### Grafana Data Sources

Open http://localhost:3000, log in, and navigate to **Connections** > **Data Sources**. Verify:

- **Prometheus** data source is connected and working
- **Loki** data source is connected and working

### Alert Rules

Open http://localhost:9090/rules and verify all 26 alert rules are loaded across 4 groups:

- `host_alerts` (15 rules)
- `container_alerts` (4 rules)
- `monitoring_stack_alerts` (5 rules)
- `predictive_alerts` (2 rules)

### Validate Configuration (Offline)

```bash
# Validate Prometheus config
make validate

# This runs:
# promtool check config configs/prometheus/prometheus.yml
# promtool check rules configs/prometheus/alert_rules.yml
# yamllint configs/
# docker compose config --quiet
```

---

## Deployment Profiles

PANOPTES uses Docker Compose profiles to control which services are started. This lets you choose the right footprint for your environment.

### Core (Default)

Starts the essential monitoring stack without log aggregation or SNMP monitoring.

```bash
docker compose up -d
```

Services: Prometheus, Grafana, Alertmanager, Node Exporter, cAdvisor, Custom Exporter, Webhook Receiver.

### With Logging

Adds Loki and Promtail for centralized log aggregation.

```bash
docker compose --profile logging up -d
```

### Full

Adds snmp_exporter for SNMP network device monitoring on top of the logging stack.

```bash
docker compose --profile full up -d
```

### SaaS Mode

Adds the nginx gateway so that remote Grafana Alloy agents can push metrics and logs into the platform.

```bash
docker compose --profile logging --profile saas up -d
```

---

## SaaS Mode Setup

SaaS mode allows remote hosts to push metrics and logs to a central PANOPTES server.

### Step 1: Start with SaaS Profile

```bash
docker compose --profile logging --profile saas up -d
```

This starts the nginx gateway on port 8080 alongside the standard logging stack.

### Step 2: Generate API Keys

```bash
bash scripts/generate-api-key.sh --tenant myhost
```

This generates a key in the format `pnpt_myhost_xxxxxxxxxxxx` and adds it to the nginx gateway configuration. Restart the gateway to pick up the new key:

```bash
docker compose restart nginx-gateway
```

### Step 3: Share the Key with the Tenant

Provide the tenant with:
- The server address: `https://panoptes.example.com:8080`
- The API key: `pnpt_myhost_xxxxxxxxxxxx`
- The tenant name: `myhost`

---

## Connecting Remote Hosts

Install the Grafana Alloy agent on any remote Linux host to push metrics and logs to PANOPTES.

### Automated Install

```bash
curl -sSL https://raw.githubusercontent.com/ada-university/panoptes/main/agent/install.sh | bash -s -- \
  --server https://panoptes.example.com:8080 \
  --key pnpt_myhost_xxxxxxxxxxxx \
  --tenant myhost
```

The script performs the following:

1. Downloads and installs the Grafana Alloy binary
2. Configures it to collect node metrics (CPU, memory, disk, network) and system logs
3. Sets the remote-write endpoint to the PANOPTES nginx gateway
4. Configures the API key in the `Authorization` header
5. Starts the agent as a systemd service

### Verifying the Connection

After installation, verify the remote host appears in Prometheus:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    if 'remote' in t.get('labels', {}).get('job', ''):
        print(f\"{t['labels']['instance']} - {t['health']}\")
"
```

The remote host's metrics will also appear in Grafana dashboards with the tenant label for filtering.

---

## Troubleshooting

### Container Will Not Start

**Symptom**: `docker compose ps` shows a container as `Exit` or `Restarting`.

```bash
# Check container logs
docker compose logs <service-name>

# Common causes:
# - Port already in use: "bind: address already in use"
#   Fix: Stop the conflicting service or change the port mapping
#
# - Permission denied on volume mount
#   Fix: Check file permissions on mounted paths
#
# - Out of memory (OOMKilled)
#   Fix: Increase mem_limit in docker-compose.yml
```

### Prometheus Cannot Scrape a Target

**Symptom**: Target shows "DOWN" in http://localhost:9090/targets.

```bash
# Verify the target is reachable from the Prometheus container
docker compose exec prometheus wget -qO- http://<target>:<port>/metrics

# Common causes:
# - Target service is not running
# - Firewall blocking the port
# - Incorrect hostname in prometheus.yml (use Docker service names, not localhost)
# - Target on a different Docker network
```

### Grafana Dashboards Are Empty

**Symptom**: Dashboards load but show "No data".

```bash
# Check Grafana data source connectivity
# Navigate to: Connections > Data Sources > Prometheus > Test

# Common causes:
# - Data source URL is incorrect (should be http://prometheus:9090 inside Docker)
# - Prometheus has no data yet (wait 1-2 minutes after initial start)
# - Time range is set incorrectly in Grafana (use "Last 15 minutes")
```

### Alertmanager Not Sending Notifications

**Symptom**: Alerts fire in Prometheus but no Telegram messages arrive.

```bash
# Check Alertmanager logs
docker compose logs alertmanager

# Check if alerts are being received
curl http://localhost:9093/api/v2/alerts

# Common causes:
# - TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is incorrect
# - Alertmanager config has syntax errors (check logs for parsing errors)
# - Network firewall blocking outbound HTTPS to Telegram API
```

### Loki Not Receiving Logs

**Symptom**: Loki Logs dashboard in Grafana shows no data.

```bash
# Check Promtail logs
docker compose logs promtail

# Verify Loki is receiving data
curl http://localhost:3100/loki/api/v1/labels
# Should return labels like {job="system", job="auth", job="docker"}

# Common causes:
# - Promtail cannot read /var/log (permission issue)
# - Docker socket not mounted for container log discovery
# - Loki is not ready (check http://localhost:3100/ready)
```

### Webhook Receiver Not Triggering Remediation

**Symptom**: Alerts with `remediation` labels fire but no playbook runs.

```bash
# Check webhook receiver logs
docker compose logs webhook-receiver

# Check remediation history
curl http://localhost:5001/history

# Check active cooldowns
curl http://localhost:5001/cooldowns

# Common causes:
# - No `remediation` label on the alert (check alert_rules.yml)
# - Cooldown is active (30-minute window after last execution)
# - Ansible inventory does not include the target host
# - SSH key not configured for Ansible access to the target
```

### K3s Pods Stuck in Pending

**Symptom**: `kubectl get pods -n panoptes` shows pods in `Pending` state.

```bash
# Check pod events
kubectl describe pod <pod-name> -n panoptes

# Common causes:
# - Insufficient resources (CPU/memory) on the node
# - PVC cannot be bound (storage class issue)
# - Image pull failure (check image name and registry access)
```

### High Memory Usage

**Symptom**: Prometheus or Loki container is OOMKilled.

```bash
# Check current memory usage
docker stats --no-stream

# Solutions:
# - Increase mem_limit in docker-compose.yml
# - Reduce Prometheus retention: --storage.tsdb.retention.time=7d
# - Reduce Loki ingestion rate in loki-config.yaml
# - Reduce the number of scrape targets or increase scrape_interval
```

### Reset Everything

To completely reset the deployment and start fresh:

```bash
# WARNING: This destroys all data (metrics, logs, dashboards)
make clean

# Then redeploy
make up
```
