#!/bin/bash
set -e

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_AUTH="${GRAFANA_AUTH:-admin:panoptes2026}"

DASHBOARD_IDS=(
    "1860:Node Exporter Full"
    "3662:Prometheus 2.0 Overview"
    "14282:cAdvisor"
    "7587:Alertmanager"
)

echo "============================================"
echo "      PANOPTES Grafana Dashboard Import"
echo "============================================"
echo ""
echo "Grafana URL: ${GRAFANA_URL}"
echo ""

DATASOURCE_NAME="Prometheus"

SUCCESS_COUNT=0
FAIL_COUNT=0

for ENTRY in "${DASHBOARD_IDS[@]}"; do
    DASHBOARD_ID="${ENTRY%%:*}"
    DASHBOARD_NAME="${ENTRY##*:}"

    echo ">>> Importing dashboard ${DASHBOARD_ID} (${DASHBOARD_NAME})..."

    DASHBOARD_JSON=$(curl -s "https://grafana.com/api/dashboards/${DASHBOARD_ID}/revisions/latest/download")

    if [ -z "$DASHBOARD_JSON" ] || echo "$DASHBOARD_JSON" | grep -q '"message"'; then
        echo "    FAILED: Could not download dashboard ${DASHBOARD_ID} from grafana.com"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    IMPORT_PAYLOAD=$(cat <<PAYLOAD_EOF
{
  "dashboard": ${DASHBOARD_JSON},
  "overwrite": true,
  "inputs": [
    {
      "name": "DS_PROMETHEUS",
      "type": "datasource",
      "pluginId": "prometheus",
      "value": "${DATASOURCE_NAME}"
    }
  ],
  "folderId": 0
}
PAYLOAD_EOF
    )

    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -u "${GRAFANA_AUTH}" \
        -H "Content-Type: application/json" \
        -X POST \
        "${GRAFANA_URL}/api/dashboards/import" \
        -d "${IMPORT_PAYLOAD}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        echo "    SUCCESS: Dashboard ${DASHBOARD_ID} (${DASHBOARD_NAME}) imported."
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "    FAILED: Dashboard ${DASHBOARD_ID} returned HTTP ${HTTP_CODE}"
        echo "    Response: ${BODY}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    echo ""
done

echo "============================================"
echo "          Import Summary"
echo "============================================"
echo "  Successful: ${SUCCESS_COUNT}"
echo "  Failed:     ${FAIL_COUNT}"
echo "============================================"
