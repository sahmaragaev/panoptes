#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <tenant-name>"
    exit 1
fi

TENANT_NAME="$1"
RANDOM_HEX=$(openssl rand -hex 12)
API_KEY="pnpt_${TENANT_NAME}_${RANDOM_HEX}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_FILE="${SCRIPT_DIR}/../configs/nginx/api-keys.yml"

printf "  - name: %s\n    key: %s\n" "$TENANT_NAME" "$API_KEY" >> "$KEYS_FILE"

echo "Generated API key for tenant '${TENANT_NAME}':"
echo "  ${API_KEY}"
echo ""
echo "Reload nginx to apply: docker compose restart nginx-gateway"
