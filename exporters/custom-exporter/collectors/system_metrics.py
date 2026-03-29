import logging
import os
import subprocess

from prometheus_client import Counter, Gauge

logger = logging.getLogger("umas-exporter.system_metrics")

PROCESS_COUNT = Gauge(
    "umas_process_count",
    "Total number of running processes",
)
ZOMBIE_COUNT = Gauge(
    "umas_zombie_count",
    "Number of zombie processes",
)
FAILED_SSH_TOTAL = Counter(
    "umas_failed_ssh_total",
    "Total number of failed SSH login attempts",
)
FD_USAGE_RATIO = Gauge(
    "umas_fd_usage_ratio",
    "Ratio of used file descriptors to maximum",
)
LOGGED_IN_USERS = Gauge(
    "umas_logged_in_users",
    "Number of currently logged in users",
)


class SystemMetricsCollector:
    def __init__(self, config):
        self._auth_log_path = config.get("auth_log_path", "/var/log/auth.log")
        self._log_position = 0

    def _collect_process_counts(self):
        try:
            proc_dirs = [
                d for d in os.listdir("/proc")
                if d.isdigit()
            ]
            PROCESS_COUNT.set(len(proc_dirs))

            zombie_count = 0
            for pid in proc_dirs:
                try:
                    with open(f"/proc/{pid}/status") as f:
                        for line in f:
                            if line.startswith("State:"):
                                if "Z" in line:
                                    zombie_count += 1
                                break
                except (FileNotFoundError, PermissionError, ProcessLookupError):
                    pass
            ZOMBIE_COUNT.set(zombie_count)
        except FileNotFoundError:
            logger.debug("/proc not available, skipping process counts")

    def _collect_failed_ssh(self):
        try:
            with open(self._auth_log_path) as f:
                f.seek(self._log_position)
                new_lines = f.readlines()
                self._log_position = f.tell()

            failed_count = sum(
                1 for line in new_lines if "Failed password" in line
            )
            if failed_count > 0:
                FAILED_SSH_TOTAL.inc(failed_count)
        except FileNotFoundError:
            logger.debug("Auth log not found at %s", self._auth_log_path)
        except PermissionError:
            logger.debug("Permission denied reading %s", self._auth_log_path)

    def _collect_fd_usage(self):
        try:
            with open("/proc/sys/fs/file-nr") as f:
                parts = f.read().strip().split()
                allocated = int(parts[0])
                maximum = int(parts[2])
                if maximum > 0:
                    FD_USAGE_RATIO.set(allocated / maximum)
        except FileNotFoundError:
            logger.debug("/proc/sys/fs/file-nr not available")

    def _collect_logged_in_users(self):
        try:
            result = subprocess.run(
                ["who"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            lines = [
                line for line in result.stdout.strip().split("\n") if line
            ]
            LOGGED_IN_USERS.set(len(lines))
        except (subprocess.TimeoutExpired, FileNotFoundError):
            logger.debug("Unable to determine logged in users")

    def collect(self):
        self._collect_process_counts()
        self._collect_failed_ssh()
        self._collect_fd_usage()
        self._collect_logged_in_users()
