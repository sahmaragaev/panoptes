#!/usr/bin/env bash
set -euo pipefail

TENANT_NAME=""
CHAT_IDS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tenant) TENANT_NAME="$2"; shift 2 ;;
        --telegram-chat) CHAT_IDS+=("$2"); shift 2 ;;
        *)
            if [ -z "$TENANT_NAME" ]; then
                TENANT_NAME="$1"; shift
            else
                echo "Unknown argument: $1" >&2; exit 1
            fi
            ;;
    esac
done

if [ -z "$TENANT_NAME" ]; then
    echo "Usage: $0 <tenant-name> [--telegram-chat CHAT_ID] [--telegram-chat CHAT_ID2]"
    exit 1
fi

RANDOM_HEX=$(openssl rand -hex 12)
API_KEY="pnpt_${TENANT_NAME}_${RANDOM_HEX}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_FILE="${SCRIPT_DIR}/../configs/nginx/api-keys.yml"

{
    printf "  - name: %s\n" "$TENANT_NAME"
    printf "    key: %s\n" "$API_KEY"
    printf "    telegram_chat_ids:\n"
    if [ ${#CHAT_IDS[@]} -eq 0 ]; then
        printf "      []\n"
    else
        for cid in "${CHAT_IDS[@]}"; do
            printf "      - \"%s\"\n" "$cid"
        done
    fi
} >> "$KEYS_FILE"

echo "Generated API key for tenant '${TENANT_NAME}':"
echo "  Key: ${API_KEY}"
if [ ${#CHAT_IDS[@]} -gt 0 ]; then
    echo "  Telegram chats: ${CHAT_IDS[*]}"
else
    echo "  Telegram chats: none (configure later in api-keys.yml)"
fi
echo ""
echo "Reload services to apply:"
echo "  docker compose restart nginx-gateway tenant-notifier"
