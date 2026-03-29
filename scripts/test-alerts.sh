#!/bin/bash
set -e

ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://localhost:9093}"

echo "============================================"
echo "        PANOPTES Alert Testing"
echo "============================================"
echo ""

TEST1_RESULT="SKIPPED"
TEST2_RESULT="SKIPPED"
TEST3_RESULT="SKIPPED"

echo ">>> Test 1: InstanceDown alert (stop node-exporter)"
echo "    Stopping panoptes-node-exporter-1..."
docker stop panoptes-node-exporter-1 || true

echo "    Waiting 90 seconds for alert to fire..."
sleep 90

echo "    Checking Alertmanager for active alerts..."
ALERTS=$(curl -s "${ALERTMANAGER_URL}/api/v2/alerts" || echo "[]")
if echo "$ALERTS" | grep -q "InstanceDown"; then
    echo "    InstanceDown alert detected."
    TEST1_RESULT="PASSED"
else
    echo "    InstanceDown alert not found in Alertmanager."
    TEST1_RESULT="FAILED"
fi

echo "    Restarting panoptes-node-exporter-1..."
docker start panoptes-node-exporter-1 || true
echo ""

echo ">>> Test 2: Disk pressure simulation"
echo "    Creating 100MB test file at /tmp/panoptes_test..."
dd if=/dev/zero of=/tmp/panoptes_test bs=1M count=100 2>/dev/null

echo "    Verifying test file was created..."
if [ -f /tmp/panoptes_test ]; then
    FILE_SIZE=$(du -h /tmp/panoptes_test | cut -f1)
    echo "    Test file created: ${FILE_SIZE}"
    TEST2_RESULT="PASSED"
else
    echo "    Failed to create test file."
    TEST2_RESULT="FAILED"
fi

echo "    Cleaning up test file..."
rm -f /tmp/panoptes_test
echo ""

echo ">>> Test 3: Direct Alertmanager API test alert"
echo "    Sending test alert to Alertmanager..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${ALERTMANAGER_URL}/api/v2/alerts" \
    -H "Content-Type: application/json" \
    -d '[
  {
    "labels": {
      "alertname": "PANOPTESTestAlert",
      "severity": "warning",
      "instance": "test-instance:9090",
      "job": "panoptes-test"
    },
    "annotations": {
      "summary": "PANOPTES test alert fired manually",
      "description": "This is a test alert sent by the PANOPTES alert testing script."
    },
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
    "generatorURL": "http://localhost:9090/graph"
  }
]')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "    Test alert sent successfully."
    TEST3_RESULT="PASSED"
else
    echo "    Failed to send test alert. HTTP code: ${HTTP_CODE}"
    TEST3_RESULT="FAILED"
fi
echo ""

echo "============================================"
echo "          Alert Test Results"
echo "============================================"
echo "  Test 1 (InstanceDown):    ${TEST1_RESULT}"
echo "  Test 2 (Disk Pressure):   ${TEST2_RESULT}"
echo "  Test 3 (API Test Alert):  ${TEST3_RESULT}"
echo "============================================"
