#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================"
echo "      PANOPTES Docker Deployment"
echo "============================================"
echo ""

cd "$PROJECT_DIR"

echo ">>> Checking for .env file..."
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "WARNING: .env file was not found. Copied from .env.example."
        echo "WARNING: Please edit .env with your actual configuration before proceeding."
        echo ""
    else
        echo "ERROR: Neither .env nor .env.example found."
        exit 1
    fi
fi

echo ">>> Building custom images..."
docker compose build custom-exporter webhook-receiver

echo ">>> Starting all services..."
docker compose up -d

echo ">>> Waiting for containers to become healthy..."
TIMEOUT=120
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT ]; do
    UNHEALTHY=$(docker compose ps --format json 2>/dev/null | grep -c '"unhealthy"\|"starting"' || true)
    TOTAL=$(docker compose ps --format json 2>/dev/null | grep -c '"running"\|"healthy"' || true)

    if [ "$UNHEALTHY" -eq 0 ] && [ "$TOTAL" -gt 0 ]; then
        echo ">>> All containers are healthy."
        break
    fi

    echo "    Waiting for containers... (${ELAPSED}s / ${TIMEOUT}s)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: Timeout reached. Some containers may not be healthy yet."
    echo ">>> Current container status:"
    docker compose ps
fi

echo ""
echo "============================================"
echo "          Deployment Complete"
echo "============================================"
echo ""
echo "Access URLs:"
echo "  Grafana:      http://localhost:3000"
echo "  Prometheus:   http://localhost:9090"
echo "  Alertmanager: http://localhost:9093"
echo "  Zabbix:       http://localhost:8081"
echo ""
echo "Default Credentials:"
echo "  Grafana:  admin / panoptes2026"
echo "  Zabbix:   Admin / zabbix"
echo ""
echo ">>> Run 'docker compose ps' to check container status."
echo "============================================"
