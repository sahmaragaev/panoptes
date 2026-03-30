import logging
import os
import threading
from datetime import datetime, timezone

import httpx
import yaml
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

KEYS_FILE = os.environ.get("KEYS_FILE", "/etc/nginx/api-keys.yml")
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_API = "https://api.telegram.org/bot{token}/sendMessage"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("tenant-notifier")

app = FastAPI(title="Panoptes Tenant Notifier")

_tenants: dict[str, list[str]] = {}
_default_chat_ids: list[str] = []
_tenants_lock = threading.Lock()


def load_tenants() -> None:
    global _default_chat_ids
    try:
        with open(KEYS_FILE) as f:
            data = yaml.safe_load(f)
        tenants = {}
        default_ids = []
        for entry in data.get("tenants", []):
            name = entry.get("name", "")
            chat_ids = [cid for cid in entry.get("telegram_chat_ids", []) if cid]
            if name:
                tenants[name] = chat_ids
            if entry.get("default") and chat_ids:
                default_ids = chat_ids
        with _tenants_lock:
            _tenants.clear()
            _tenants.update(tenants)
            _default_chat_ids = default_ids
        logger.info("Loaded %d tenants from %s", len(tenants), KEYS_FILE)
    except FileNotFoundError:
        logger.warning("Keys file not found: %s", KEYS_FILE)
    except Exception:
        logger.exception("Failed to load tenants")


def get_chat_ids(tenant: str) -> list[str]:
    with _tenants_lock:
        if tenant:
            ids = _tenants.get(tenant, [])
            if ids:
                return ids
        return list(_default_chat_ids)


def format_message(alert: dict, status: str) -> str:
    labels = alert.get("labels", {})
    annotations = alert.get("annotations", {})
    severity = labels.get("severity", "unknown").upper()
    alertname = labels.get("alertname", "unknown")
    instance = labels.get("instance", "")
    summary = annotations.get("summary", "")
    description = annotations.get("description", "")

    tag = "RESOLVED" if status == "resolved" else severity
    lines = [f"[{tag}] {alertname}"]
    if instance:
        lines[0] += f" ({instance})"
    if summary:
        lines.append(summary)
    if description:
        lines.append(description)
    return "\n".join(lines)


def send_telegram(chat_id: str, message: str) -> bool:
    if not BOT_TOKEN or not chat_id:
        logger.warning("Missing bot token or chat_id, skipping")
        return False
    try:
        url = TELEGRAM_API.format(token=BOT_TOKEN)
        resp = httpx.post(url, json={"chat_id": chat_id, "text": message}, timeout=10)
        if resp.status_code == 200:
            return True
        logger.error("Telegram API returned %d: %s", resp.status_code, resp.text)
        return False
    except Exception:
        logger.exception("Failed to send Telegram message to %s", chat_id)
        return False


@app.on_event("startup")
async def startup():
    load_tenants()


@app.post("/reload")
async def reload_tenants():
    load_tenants()
    with _tenants_lock:
        count = len(_tenants)
    return {"status": "reloaded", "tenants": count}


@app.post("/webhook")
async def webhook(request: Request):
    payload = await request.json()
    alerts = payload.get("alerts", [])
    group_status = payload.get("status", "firing")
    results = []

    for alert in alerts:
        labels = alert.get("labels", {})
        tenant = labels.get("tenant", "")
        alertname = labels.get("alertname", "unknown")
        status = alert.get("status", group_status)

        chat_ids = get_chat_ids(tenant)
        message = format_message(alert, status)

        sent_to = []
        for chat_id in chat_ids:
            if send_telegram(chat_id, message):
                sent_to.append(chat_id)

        results.append({
            "alert": alertname,
            "tenant": tenant or "default",
            "sent_to": len(sent_to),
            "total_chats": len(chat_ids),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

    return JSONResponse(content={"results": results})


@app.get("/health")
async def health():
    return {"status": "healthy"}
