#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$PROJECT_DIR"

echo -e "${BLUE}"
echo "  _   _ __  __    _    ____    ____  _____ __  __  ___  "
echo " | | | |  \/  |  / \  / ___|  |  _ \| ____|  \/  |/ _ \ "
echo " | | | | |\/| | / _ \ \___ \  | | | |  _| | |\/| | | | |"
echo " | |_| | |  | |/ ___ \ ___) | | |_| | |___| |  | | |_| |"
echo "  \___/|_|  |_/_/   \_\____/  |____/|_____|_|  |_|\___/ "
echo -e "${NC}"
echo ""

pause_and_continue() {
    echo ""
    echo -e "${YELLOW}>>> $1${NC}"
    echo -e "${GREEN}    Press Enter to continue...${NC}"
    read -r
}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Step 1: System Status${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${GREEN}>>> Docker Compose status:${NC}"
docker compose ps
echo ""

echo -e "${GREEN}>>> Prometheus targets:${NC}"
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool 2>/dev/null || curl -s http://localhost:9090/api/v1/targets
echo ""

pause_and_continue "Step 2: Simulate CPU spike using stress-ng"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Step 2: CPU Spike Simulation${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${RED}>>> Running stress-ng --cpu 4 --timeout 30s ...${NC}"
stress-ng --cpu 4 --timeout 30s &
STRESS_PID=$!

echo -e "${YELLOW}>>> stress-ng is running in the background (PID: ${STRESS_PID})${NC}"
echo -e "${GREEN}>>> Open Grafana to observe CPU usage: http://localhost:3000${NC}"
echo -e "${YELLOW}>>> Waiting for stress test to complete...${NC}"
wait $STRESS_PID || true
echo -e "${GREEN}>>> CPU spike simulation complete.${NC}"

pause_and_continue "Step 3: Simulate service failure (stop node-exporter)"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Step 3: Service Failure Simulation${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${RED}>>> Stopping node-exporter container...${NC}"
docker compose stop node-exporter

echo -e "${YELLOW}>>> Waiting 60 seconds for InstanceDown alert to fire...${NC}"
sleep 60

echo -e "${GREEN}>>> Checking Prometheus alerts:${NC}"
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool 2>/dev/null || curl -s http://localhost:9090/api/v1/alerts
echo ""

echo -e "${GREEN}>>> Restarting node-exporter...${NC}"
docker compose start node-exporter
echo -e "${GREEN}>>> node-exporter has been restarted.${NC}"

pause_and_continue "Step 4: Show auto-remediation via webhook-receiver"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Step 4: Auto-Remediation${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${YELLOW}>>> Triggering a test alert to the webhook-receiver...${NC}"
curl -s -X POST http://localhost:9093/api/v2/alerts \
    -H "Content-Type: application/json" \
    -d '[
  {
    "labels": {
      "alertname": "DiskSpaceLow",
      "severity": "critical",
      "instance": "localhost:9100",
      "job": "node-exporter"
    },
    "annotations": {
      "summary": "Disk space critically low on localhost",
      "description": "Demo disk pressure alert for auto-remediation test."
    },
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'"
  }
]'
echo ""

echo -e "${YELLOW}>>> Waiting 10 seconds for webhook processing...${NC}"
sleep 10

echo -e "${GREEN}>>> Webhook-receiver logs:${NC}"
docker compose logs --tail=30 webhook-receiver
echo ""

pause_and_continue "Step 5: Show log analysis via Loki"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Step 5: Log Analysis${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${GREEN}>>> Querying Loki for recent logs...${NC}"
LOKI_QUERY=$(printf '%s' '{job=~".+"}' | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo '%7Bjob%3D~%22.%2B%22%7D')
curl -s "http://localhost:3100/loki/api/v1/query_range?query=${LOKI_QUERY}&limit=20&since=1h" | python3 -m json.tool 2>/dev/null || echo "Loki query completed (raw output may not be available)"
echo ""

pause_and_continue "Step 6: Demo Summary"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Step 6: Demo Summary & Cleanup${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${GREEN}>>> Ensuring all services are running...${NC}"
docker compose up -d
echo ""

echo -e "${GREEN}>>> Final container status:${NC}"
docker compose ps
echo ""

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}          UMAS Demo Complete${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "${GREEN}Access URLs:${NC}"
echo -e "  Grafana:      ${YELLOW}http://localhost:3000${NC}"
echo -e "  Prometheus:   ${YELLOW}http://localhost:9090${NC}"
echo -e "  Alertmanager: ${YELLOW}http://localhost:9093${NC}"
echo -e "  Zabbix:       ${YELLOW}http://localhost:8081${NC}"
echo -e "  Loki:         ${YELLOW}http://localhost:3100${NC}"
echo ""
echo -e "${GREEN}Thank you for watching the UMAS demo!${NC}"
echo ""
