import logging
import subprocess
import os
from datetime import datetime, timedelta
from typing import Any

import yaml
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

with open(os.path.join(os.path.dirname(__file__), "config.yaml"), "r") as f:
    CONFIG = yaml.safe_load(f)

COOLDOWN_DURATION = timedelta(minutes=CONFIG["cooldown"]["duration_minutes"])
PLAYBOOK_DIR = CONFIG["ansible"]["playbook_dir"]
INVENTORY = CONFIG["ansible"]["inventory"]

logging.basicConfig(
    filename=CONFIG["logging"]["file"],
    level=getattr(logging, CONFIG["logging"]["level"], logging.INFO),
    format="%(asctime)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("remediation")

console_handler = logging.StreamHandler()
console_handler.setLevel(getattr(logging, CONFIG["logging"]["level"], logging.INFO))
console_handler.setFormatter(logging.Formatter("%(asctime)s - %(levelname)s - %(message)s"))
logger.addHandler(console_handler)

app = FastAPI(title="UMAS Remediation Webhook Receiver")

PLAYBOOK_MAP = {
    "disk_cleanup": "playbooks/disk_cleanup.yml",
    "restart_service": "playbooks/restart_service.yml",
    "clear_memory": "playbooks/clear_memory.yml",
    "rotate_logs": "playbooks/rotate_logs.yml",
    "docker_cleanup": "playbooks/docker_cleanup.yml",
}

cooldowns: dict[str, datetime] = {}
history: list[dict[str, Any]] = []
MAX_HISTORY = 50


def is_in_cooldown(host: str, remediation: str) -> bool:
    key = f"{host}:{remediation}"
    if key in cooldowns:
        if datetime.utcnow() - cooldowns[key] < COOLDOWN_DURATION:
            return True
        del cooldowns[key]
    return False


def set_cooldown(host: str, remediation: str) -> None:
    key = f"{host}:{remediation}"
    cooldowns[key] = datetime.utcnow()


def run_playbook(playbook: str, target_host: str, extra_vars: dict | None = None) -> dict:
    playbook_path = os.path.join(PLAYBOOK_DIR, os.path.basename(playbook))
    cmd = [
        "ansible-playbook",
        playbook_path,
        "-i", INVENTORY,
        "--extra-vars", f"target_host={target_host}",
    ]
    if extra_vars:
        for k, v in extra_vars.items():
            cmd.extend(["--extra-vars", f"{k}={v}"])

    logger.info("Running: %s", " ".join(cmd))

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,
        )
        return {
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired:
        logger.error("Playbook timed out: %s", playbook)
        return {
            "returncode": -1,
            "stdout": "",
            "stderr": "Playbook execution timed out after 300 seconds",
        }


def add_history(entry: dict) -> None:
    history.insert(0, entry)
    while len(history) > MAX_HISTORY:
        history.pop()


@app.post("/webhook")
async def webhook(request: Request):
    payload = await request.json()
    alerts = payload.get("alerts", [])
    results = []

    for alert in alerts:
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        remediation = labels.get("remediation", annotations.get("remediation", ""))
        instance = labels.get("instance", "localhost")
        target_host = instance.split(":")[0]
        alert_name = labels.get("alertname", "unknown")
        service_name = labels.get("service_name", labels.get("job", "unknown"))

        if not remediation:
            logger.warning("No remediation label for alert: %s", alert_name)
            results.append({
                "alert": alert_name,
                "status": "skipped",
                "reason": "no remediation label",
            })
            continue

        if remediation not in PLAYBOOK_MAP:
            logger.warning("Unknown remediation: %s", remediation)
            results.append({
                "alert": alert_name,
                "status": "skipped",
                "reason": f"unknown remediation: {remediation}",
            })
            continue

        if is_in_cooldown(target_host, remediation):
            logger.info("Cooldown active for %s on %s", remediation, target_host)
            results.append({
                "alert": alert_name,
                "status": "skipped",
                "reason": "cooldown active",
            })
            continue

        logger.info("Executing %s for alert %s on %s", remediation, alert_name, target_host)

        extra_vars = {}
        if remediation == "restart_service":
            extra_vars["service_name"] = service_name

        playbook_result = run_playbook(PLAYBOOK_MAP[remediation], target_host, extra_vars)
        set_cooldown(target_host, remediation)

        entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "alert": alert_name,
            "remediation": remediation,
            "target_host": target_host,
            "returncode": playbook_result["returncode"],
            "status": "success" if playbook_result["returncode"] == 0 else "failed",
        }
        add_history(entry)

        results.append({
            "alert": alert_name,
            "remediation": remediation,
            "target_host": target_host,
            "status": entry["status"],
        })

    return JSONResponse(content={"results": results})


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.get("/history")
async def get_history():
    return {"history": history}


@app.get("/cooldowns")
async def get_cooldowns():
    now = datetime.utcnow()
    active = {}
    expired_keys = []

    for key, timestamp in cooldowns.items():
        elapsed = now - timestamp
        if elapsed < COOLDOWN_DURATION:
            remaining = COOLDOWN_DURATION - elapsed
            active[key] = {
                "started": timestamp.isoformat(),
                "remaining_seconds": int(remaining.total_seconds()),
            }
        else:
            expired_keys.append(key)

    for key in expired_keys:
        del cooldowns[key]

    return {"cooldowns": active}
