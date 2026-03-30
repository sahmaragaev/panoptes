# PANOPTES Operational Runbook

This runbook provides investigation and resolution procedures for every alert configured in PANOPTES. Each entry includes the alert context, impact assessment, diagnostic steps, resolution actions, and escalation path.

---

## Table of Contents

**Host Alerts**
1. [InstanceDown](#instancedown)
2. [HighCPUUsage](#highcpuusage)
3. [CriticalCPUUsage](#criticalcpuusage)
4. [HighMemoryUsage](#highmemoryusage)
5. [HostOutOfMemory](#hostoutofmemory)
6. [DiskSpaceWarning](#diskspacewarning)
7. [DiskSpaceCritical](#diskspacecritical)
8. [DiskFillingUp](#diskfillingup)
9. [HighSystemLoad](#highsystemload)
10. [TooManyOpenFiles](#toomanyopenfiles)
11. [NetworkReceiveErrors](#networkreceiveerrors)
12. [HighSwapUsage](#highswapusage)
13. [SystemdServiceFailed](#systemdservicefailed)
14. [HostClockSkew](#hostclockskew)
15. [OOMKillDetected](#oomkilldetected)

**Container Alerts**
16. [ContainerHighCPU](#containerhighcpu)
17. [ContainerHighMemory](#containerhighmemory)
18. [ContainerRestarting](#containerrestarting)
19. [ContainerKilled](#containerkilled)

**Monitoring Stack Alerts**
20. [PrometheusTargetDown](#prometheustargetdown)
21. [PrometheusHighMemory](#prometheushighmemory)
22. [AlertmanagerNotificationFailed](#alertmanagernotificationfailed)
23. [LokiIngestionRate](#lokiingestionrate)
24. [GrafanaDown](#grafanadown)

**Predictive Alerts**
25. [DiskWillFillIn4Hours](#diskwillfillin4hours)
26. [MemoryLeakDetected](#memoryleakdetected)

**Reference**
- [Common Troubleshooting Commands](#common-troubleshooting-commands)
- [Log Locations](#log-locations)
- [Escalation Procedures](#escalation-procedures)

---

## Host Alerts

---

### InstanceDown

- **Severity**: Critical
- **Expression**: `up == 0`
- **Duration**: 1 minute
- **Auto-Remediation**: No

#### What

A monitored target is not responding to Prometheus scrapes. The `up` metric, which Prometheus sets automatically for each scrape target, has been 0 for more than 1 minute.

#### Impact

- Metrics collection has stopped for this target
- Any alerts that depend on metrics from this target will not fire (the data is absent, not zero)
- Grafana dashboards will show gaps for this target
- If the target is a core monitoring component (Grafana, Loki, Alertmanager), observability may be degraded

#### Investigation

1. **Check if the host is reachable:**
   ```bash
   ping <target_host>
   ```

2. **Check if the exporter process is running on the target:**
   ```bash
   ssh <target_host> "systemctl status node_exporter"
   # For Docker-based exporters:
   docker ps | grep <exporter_name>
   ```

3. **Check if the exporter port is accessible from the Prometheus host:**
   ```bash
   curl -s http://<target_host>:<port>/metrics | head -5
   # Or from inside the Prometheus container:
   docker compose exec prometheus wget -qO- http://<target>:<port>/metrics | head -5
   ```

4. **Check firewall rules on the target host:**
   ```bash
   ssh <target_host> "ufw status"
   ssh <target_host> "iptables -L -n | grep <port>"
   ```

5. **Check Prometheus logs for scrape errors:**
   ```bash
   docker compose logs prometheus | grep "<target>"
   ```

6. **Check the Prometheus targets page:**
   Open http://localhost:9090/targets and look for error messages next to the target.

#### Resolution

- If the host is unreachable: Check networking, check if the host is powered on, check the hypervisor/cloud console
- If the exporter is stopped: Restart the exporter service
  ```bash
  ssh <target_host> "systemctl restart node_exporter"
  ```
- If the port is blocked: Add a firewall rule
  ```bash
  ssh <target_host> "ufw allow 9100"
  ```
- If the Docker container is stopped:
  ```bash
  docker start <container_name>
  ```

#### Escalation

If the host is unreachable and not responding to any network probes, escalate to the infrastructure team. Include the host IP, last known status, and the timestamp when the alert fired.

---

### HighCPUUsage

- **Severity**: Warning
- **Expression**: `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

The average CPU utilization across all cores on the target host has been above 85% for 5 minutes.

#### Impact

- System responsiveness may be degraded
- Applications may experience increased latency
- If sustained, may lead to CriticalCPUUsage alert escalation

#### Investigation

1. **Identify the top CPU-consuming processes:**
   ```bash
   ssh <target_host> "top -bn1 | head -20"
   ssh <target_host> "ps aux --sort=-%cpu | head -15"
   ```

2. **Check for runaway processes or cron jobs:**
   ```bash
   ssh <target_host> "journalctl -u cron --since '1 hour ago'"
   ```

3. **Check if the load is expected (batch jobs, builds, backups):**
   ```bash
   ssh <target_host> "crontab -l"
   ```

4. **Check the Grafana Node Detail dashboard** for historical CPU patterns:
   Navigate to the Node Detail dashboard and select the affected instance.

#### Resolution

- If caused by a known batch job: Wait for completion, or reschedule to off-peak hours
- If caused by a runaway process:
  ```bash
  ssh <target_host> "kill <PID>"
  ```
- If caused by legitimate load increase: Consider vertical scaling (more vCPUs) or horizontal scaling (distribute the workload)
- If caused by a misconfigured application: Fix the application configuration and restart

#### Escalation

If CPU usage remains above 85% after investigation and no clear cause is found, escalate to the application team responsible for the workload on the affected host.

---

### CriticalCPUUsage

- **Severity**: Critical
- **Expression**: `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 95`
- **Duration**: 2 minutes
- **Auto-Remediation**: No

#### What

CPU utilization has exceeded 95% for 2 minutes. The system is nearly fully saturated.

#### Impact

- System is effectively unresponsive to new requests
- SSH sessions may be extremely slow or time out
- Services will experience severe latency or timeouts
- OOM killer may activate if memory pressure also increases

#### Investigation

Follow the same steps as [HighCPUUsage](#highcpuusage), with added urgency.

1. **If SSH is slow, try lower-overhead commands:**
   ```bash
   ssh <target_host> "pidstat 1 5"
   ```

2. **Check for fork bombs or infinite loops:**
   ```bash
   ssh <target_host> "ps aux | wc -l"   # Abnormally high count = possible fork bomb
   ```

#### Resolution

- Immediately kill the highest CPU-consuming non-critical process:
  ```bash
  ssh <target_host> "kill -9 <PID>"
  ```
- If SSH is unresponsive, use out-of-band access (cloud console, IPMI, KVM) to access the host
- After stabilizing, investigate root cause and implement preventive measures (resource limits, cgroups)

#### Escalation

Immediate escalation to the infrastructure team if the host becomes unresponsive to SSH. Provide the host IP and alert timestamp.

---

### HighMemoryUsage

- **Severity**: Warning
- **Expression**: `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

Memory utilization (including buffers/cache) has been above 85% for 5 minutes. The `MemAvailable` metric accounts for reclaimable memory.

#### Impact

- System may start using swap, degrading performance
- Applications may fail to allocate memory if usage continues to climb
- Risk of OOM killer activation

#### Investigation

1. **Check memory breakdown:**
   ```bash
   ssh <target_host> "free -h"
   ```

2. **Identify top memory consumers:**
   ```bash
   ssh <target_host> "ps aux --sort=-%mem | head -15"
   ```

3. **Check for memory leaks (processes with growing RSS):**
   ```bash
   ssh <target_host> "smem -t -k -s rss | tail -15"
   ```

4. **Check swap usage:**
   ```bash
   ssh <target_host> "swapon --show"
   ```

#### Resolution

- Clear page cache (safe, non-destructive):
  ```bash
  ssh <target_host> "sync && echo 3 > /proc/sys/vm/drop_caches"
  ```
- Restart memory-hungry applications that may have a leak
- If the host needs more memory: Scale vertically or migrate workloads

#### Escalation

If memory usage does not decrease after cache clearing and process investigation, escalate to the application team with a list of top memory consumers.

---

### HostOutOfMemory

- **Severity**: Critical
- **Expression**: `(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10`
- **Duration**: 2 minutes
- **Auto-Remediation**: Yes (`clear_memory`)

#### What

Available memory has dropped below 10% of total memory. The system is critically low on memory.

#### Impact

- OOM killer will likely activate, killing processes
- Services may crash unexpectedly
- SSH sessions may freeze
- System may become completely unresponsive

#### Investigation

1. **Check if the auto-remediation playbook ran:**
   ```bash
   curl http://localhost:5001/history
   ```

2. **Check OOM killer activity:**
   ```bash
   ssh <target_host> "dmesg | grep -i oom | tail -20"
   ```

3. **Check which processes were killed:**
   ```bash
   ssh <target_host> "journalctl -k | grep -i 'killed process'"
   ```

#### Resolution

The `clear_memory` Ansible playbook automatically:
1. Syncs filesystems
2. Drops page cache (`echo 3 > /proc/sys/vm/drop_caches`)
3. Checks memory usage after clearing
4. Restarts memory-heavy services (apache2, mysql, redis-server) if usage is still above 90%

If auto-remediation is insufficient:
- Manually kill the largest memory consumer
- Add swap space as a temporary buffer
- Scale the host vertically

#### Escalation

If memory does not recover after auto-remediation and manual intervention, escalate to the infrastructure team for emergency capacity increase.

---

### DiskSpaceWarning

- **Severity**: Warning
- **Expression**: `disk usage > 80%` (excludes tmpfs and overlay)
- **Duration**: 10 minutes
- **Auto-Remediation**: No

#### What

A filesystem on the target host has been above 80% utilization for 10 minutes.

#### Impact

- If usage continues to grow, will trigger DiskSpaceCritical
- Applications that write to this filesystem may start failing if disk fills completely
- Databases may crash or corrupt data if they cannot write

#### Investigation

1. **Check disk usage by filesystem:**
   ```bash
   ssh <target_host> "df -h"
   ```

2. **Find the largest files and directories:**
   ```bash
   ssh <target_host> "du -sh /* 2>/dev/null | sort -rh | head -15"
   ssh <target_host> "find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | head -20"
   ```

3. **Check log file sizes:**
   ```bash
   ssh <target_host> "du -sh /var/log/*"
   ```

4. **Check Docker disk usage:**
   ```bash
   ssh <target_host> "docker system df"
   ```

#### Resolution

- Clean up old log files:
  ```bash
  ssh <target_host> "journalctl --vacuum-size=200M"
  ```
- Clean Docker resources:
  ```bash
  ssh <target_host> "docker system prune -af"
  ```
- Remove old packages:
  ```bash
  ssh <target_host> "apt autoclean && apt autoremove -y"
  ```
- Delete temporary or obsolete files identified during investigation

#### Escalation

If disk space cannot be reduced below 80% through cleanup, request additional storage from the infrastructure team.

---

### DiskSpaceCritical

- **Severity**: Critical
- **Expression**: `disk usage > 90%` (excludes tmpfs and overlay)
- **Duration**: 5 minutes
- **Auto-Remediation**: Yes (`disk_cleanup`)

#### What

A filesystem has been above 90% utilization for 5 minutes. Service disruption is imminent.

#### Impact

- Applications may fail to write data
- Databases may crash or refuse new connections
- System logs may stop being written
- Docker may fail to create new containers

#### Investigation

1. **Check if the auto-remediation playbook ran:**
   ```bash
   curl http://localhost:5001/history
   ```

2. Follow the same investigation steps as [DiskSpaceWarning](#diskspacewarning).

#### Resolution

The `disk_cleanup` Ansible playbook automatically:
1. Runs `docker system prune -af`
2. Truncates log files larger than 100 MB
3. Vacuums systemd journal to 200 MB
4. Runs `apt autoclean`
5. Prunes dangling Docker images

If auto-remediation is insufficient:
- Manually identify and remove the largest files
- Resize the volume or add additional storage
- Move large directories to a different volume

#### Escalation

If disk usage cannot be reduced below 90%, immediately escalate to the infrastructure team. The host is at risk of service outage.

---

### DiskFillingUp

- **Severity**: Warning
- **Expression**: `predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0`
- **Duration**: 30 minutes
- **Auto-Remediation**: No

#### What

Based on the trend over the last 6 hours, the disk is predicted to fill completely within 24 hours.

#### Impact

- Not yet impacting services, but will if the trend continues
- Allows proactive remediation before the disk is full

#### Investigation

1. **Check current disk usage and growth rate:**
   ```bash
   ssh <target_host> "df -h"
   ```

2. **Identify what is growing:**
   ```bash
   ssh <target_host> "du -sh /var/log/* | sort -rh | head -10"
   ssh <target_host> "docker system df"
   ```

3. **Check the Grafana Node Detail dashboard** for the disk usage trend graph.

4. **Check for scheduled jobs that may fill disk:**
   ```bash
   ssh <target_host> "crontab -l"
   ```

#### Resolution

- Address the source of disk growth (runaway logging, large backups, growing database)
- Set up log rotation if not configured
- Enable Docker log size limits
- Schedule regular cleanup jobs

#### Escalation

If the source of growth cannot be identified or controlled, inform the infrastructure team about the predicted timeline and request additional storage.

---

### HighSystemLoad

- **Severity**: Warning
- **Expression**: `node_load1 > count by(instance) (node_cpu_seconds_total{mode="idle"})`
- **Duration**: 10 minutes
- **Auto-Remediation**: No

#### What

The 1-minute load average exceeds the number of CPU cores for 10 minutes. This means more processes are waiting for CPU time than can be served.

#### Impact

- Process scheduling delays
- Increased response times for all applications
- May indicate I/O wait or excessive process count

#### Investigation

1. **Check load averages and CPU count:**
   ```bash
   ssh <target_host> "uptime"
   ssh <target_host> "nproc"
   ```

2. **Check for I/O wait (high wa% indicates disk bottleneck):**
   ```bash
   ssh <target_host> "iostat -x 1 5"
   ssh <target_host> "top -bn1 | head -5"  # Look at %wa
   ```

3. **Check for process count explosion:**
   ```bash
   ssh <target_host> "ps aux | wc -l"
   ```

4. **Check for blocked processes:**
   ```bash
   ssh <target_host> "vmstat 1 5"  # Look at the 'b' (blocked) column
   ```

#### Resolution

- If caused by I/O wait: Identify the I/O-heavy process, optimize database queries, upgrade to faster storage (SSD)
- If caused by too many processes: Reduce concurrency, implement rate limiting, kill unnecessary processes
- If caused by CPU saturation: Follow [HighCPUUsage](#highcpuusage) resolution

#### Escalation

If load remains high and the cause is unclear, escalate to both the infrastructure team and application team.

---

### TooManyOpenFiles

- **Severity**: Warning
- **Expression**: `node_filefd_allocated / node_filefd_maximum * 100 > 80`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

The ratio of allocated file descriptors to the system maximum exceeds 80%. Approaching the limit will cause "too many open files" errors.

#### Impact

- Applications may fail to open new files, sockets, or pipes
- Network connections may be refused
- Database connections may fail

#### Investigation

1. **Check current file descriptor usage:**
   ```bash
   ssh <target_host> "cat /proc/sys/fs/file-nr"
   # Output: <allocated> <free> <max>
   ```

2. **Find processes with the most open files:**
   ```bash
   ssh <target_host> "for pid in /proc/[0-9]*/fd; do echo \$(ls \$pid 2>/dev/null | wc -l) \$pid; done | sort -rn | head -15"
   ```

3. **Check per-process limits:**
   ```bash
   ssh <target_host> "ulimit -n"
   ```

#### Resolution

- Restart the process with the most open file descriptors (may indicate a file descriptor leak)
- Increase the system limit:
  ```bash
  ssh <target_host> "sysctl -w fs.file-max=500000"
  echo "fs.file-max = 500000" >> /etc/sysctl.conf
  ```
- Increase per-process limits in `/etc/security/limits.conf`

#### Escalation

If the process with the most file descriptors is a production application, escalate to the application team to investigate a possible file descriptor leak.

---

### NetworkReceiveErrors

- **Severity**: Warning
- **Expression**: `rate(node_network_receive_errs_total[5m]) > 0`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

A network interface is experiencing persistent receive errors. The error rate has been greater than 0 for 5 minutes.

#### Impact

- Packet loss may cause retransmissions and increased latency
- Applications relying on network communication may experience degraded performance
- May indicate hardware failure (NIC, cable, switch port)

#### Investigation

1. **Check interface error counters:**
   ```bash
   ssh <target_host> "ip -s link show"
   ssh <target_host> "ethtool -S <interface>"
   ```

2. **Check for link speed negotiation issues:**
   ```bash
   ssh <target_host> "ethtool <interface>"  # Check Speed and Duplex
   ```

3. **Check system logs for network errors:**
   ```bash
   ssh <target_host> "dmesg | grep -i 'eth\|link\|network' | tail -20"
   ```

4. **Check the switch port on the other end** (if accessible).

#### Resolution

- If errors are intermittent: Monitor and check cabling
- If link speed is wrong: Force the correct speed/duplex
- If hardware failure: Replace the cable, NIC, or switch port
- If virtual environment: Check the hypervisor network configuration

#### Escalation

If hardware replacement is needed, escalate to the infrastructure/network team with the interface name, error counts, and dmesg output.

---

### HighSwapUsage

- **Severity**: Warning
- **Expression**: `swap usage > 80%` (only fires if swap is configured)
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

Swap utilization has been above 80% for 5 minutes. The system is relying heavily on swap space, which is orders of magnitude slower than RAM.

#### Impact

- Severe performance degradation due to disk I/O for memory operations
- Processes that are swapped out will be extremely slow when accessed
- May lead to OOM kills if swap also fills

#### Investigation

1. **Check swap usage:**
   ```bash
   ssh <target_host> "free -h"
   ssh <target_host> "swapon --show"
   ```

2. **Check which processes are using swap:**
   ```bash
   ssh <target_host> "for f in /proc/*/status; do awk '/Name/{n=\$2} /VmSwap/{s=\$2} END{if(s>0) print s,n}' \$f 2>/dev/null; done | sort -rn | head -10"
   ```

3. **Check the swappiness setting:**
   ```bash
   ssh <target_host> "cat /proc/sys/vm/swappiness"
   ```

#### Resolution

- Reduce swappiness to prefer RAM over swap:
  ```bash
  ssh <target_host> "sysctl -w vm.swappiness=10"
  ```
- Clear page cache to free RAM:
  ```bash
  ssh <target_host> "sync && echo 3 > /proc/sys/vm/drop_caches"
  ```
- Restart the top swap-consuming processes
- Add more RAM to the host

#### Escalation

If swap usage does not decrease after intervention, the host needs more physical memory. Escalate to the infrastructure team.

---

### SystemdServiceFailed

- **Severity**: Critical
- **Expression**: `node_systemd_unit_state{state="failed"} == 1`
- **Duration**: 2 minutes
- **Auto-Remediation**: Yes (`restart_service`)

#### What

A systemd service has entered a failed state on the target host.

#### Impact

- The failed service is not running, which may affect dependent services
- If the service is critical (e.g., Docker, SSH, database), the impact can be severe
- The alert label `name` identifies which service has failed

#### Investigation

1. **Check if the auto-remediation playbook ran:**
   ```bash
   curl http://localhost:5001/history
   ```

2. **Check the service status:**
   ```bash
   ssh <target_host> "systemctl status <service_name>"
   ```

3. **Check the service logs:**
   ```bash
   ssh <target_host> "journalctl -u <service_name> --since '30 minutes ago'"
   ```

4. **Check for configuration errors:**
   ```bash
   ssh <target_host> "systemd-analyze verify <service_name>"
   ```

#### Resolution

The `restart_service` Ansible playbook automatically:
1. Restarts the failed service via systemd
2. Waits for the service to become active (retries 5 times with 5-second delay)
3. Reports the final service status

If auto-remediation fails:
- Check the service logs for the root cause (configuration error, missing dependency, port conflict)
- Fix the underlying issue and restart manually:
  ```bash
  ssh <target_host> "systemctl restart <service_name>"
  ```
- If the service repeatedly fails, it may need a configuration fix rather than a restart

#### Escalation

If the service cannot be restarted and the failure is in a critical service, escalate to the team responsible for that service.

---

### HostClockSkew

- **Severity**: Warning
- **Expression**: `abs(node_timex_offset_seconds) > 0.05`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

The system clock on the host is skewed by more than 50 milliseconds from the NTP reference.

#### Impact

- TLS certificate validation may fail if skew is large
- Log timestamps will be inaccurate, making correlation difficult
- Distributed systems that depend on time synchronization may behave incorrectly
- Kerberos authentication (Active Directory) will fail if skew exceeds 5 minutes

#### Investigation

1. **Check the current time offset:**
   ```bash
   ssh <target_host> "timedatectl"
   ssh <target_host> "chronyc tracking"  # or ntpq -p
   ```

2. **Check if NTP is running:**
   ```bash
   ssh <target_host> "systemctl status chronyd"  # or ntp or systemd-timesyncd
   ```

3. **Check NTP sources:**
   ```bash
   ssh <target_host> "chronyc sources -v"
   ```

#### Resolution

- Force an immediate time sync:
  ```bash
  ssh <target_host> "chronyc makestep"
  # or
  ssh <target_host> "ntpdate -b pool.ntp.org"
  ```
- Ensure NTP is enabled and configured:
  ```bash
  ssh <target_host> "timedatectl set-ntp true"
  ```
- Check if the NTP server is reachable from the host

#### Escalation

If NTP synchronization repeatedly fails, there may be a network issue blocking UDP port 123. Escalate to the network team.

---

### OOMKillDetected

- **Severity**: Warning
- **Expression**: `increase(node_vmstat_oom_kill[5m]) > 0`
- **Duration**: 0 minutes (instant)
- **Auto-Remediation**: No

#### What

The Linux kernel's OOM (Out of Memory) killer has terminated a process to free memory. This is a reactive kernel mechanism that fires when the system is completely out of memory.

#### Impact

- A process has been killed unexpectedly
- If the killed process was a critical service, that service is now down
- Data loss is possible if the killed process had unsaved state

#### Investigation

1. **Identify the killed process:**
   ```bash
   ssh <target_host> "dmesg | grep -i 'oom\|killed process' | tail -10"
   ssh <target_host> "journalctl -k --since '10 minutes ago' | grep -i oom"
   ```

2. **Check current memory state:**
   ```bash
   ssh <target_host> "free -h"
   ```

3. **Check if the killed process needs to be restarted:**
   ```bash
   ssh <target_host> "systemctl status <killed_service>"
   ```

#### Resolution

- Restart the killed service if it is critical
- Investigate why memory was exhausted (see [HighMemoryUsage](#highmemoryusage))
- Set OOM score adjustments to protect critical processes:
  ```bash
  echo -1000 > /proc/<pid>/oom_score_adj  # Protect a process from OOM killer
  ```
- Add more RAM or reduce the memory footprint of applications

#### Escalation

If OOM kills recur and affect critical services, escalate to both the infrastructure team (for capacity) and the application team (for memory optimization).

---

## Container Alerts

---

### ContainerHighCPU

- **Severity**: Warning
- **Expression**: `sum by(name) (rate(container_cpu_usage_seconds_total{name!=""}[5m])) * 100 > 80`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

A Docker container is using more than 80% of its allocated CPU time for 5 minutes.

#### Impact

- The container may be slow to respond
- Other containers on the same host may be starved of CPU if no limits are set

#### Investigation

1. **Check container resource usage:**
   ```bash
   docker stats --no-stream | sort -k3 -rh | head -10
   ```

2. **Check the container's CPU limit:**
   ```bash
   docker inspect <container_name> | grep -i cpu
   ```

3. **Check processes inside the container:**
   ```bash
   docker top <container_name>
   ```

4. **Check container logs for errors or unusual activity:**
   ```bash
   docker logs --tail 50 <container_name>
   ```

#### Resolution

- If the container has a CPU limit, consider increasing it in `docker-compose.yml`
- If the container does not have a CPU limit, add one to prevent host saturation
- Restart the container if the issue is a runaway process:
  ```bash
  docker restart <container_name>
  ```

#### Escalation

If the container is part of the monitoring stack, escalate to the PANOPTES team. If it is an application container, escalate to the application team.

---

### ContainerHighMemory

- **Severity**: Warning
- **Expression**: `container memory usage > 85% of memory limit`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

A container is using more than 85% of its configured memory limit. If it reaches 100%, Docker will OOM-kill the container.

#### Impact

- The container is at risk of being killed by Docker's OOM handler
- Service interruption if the container is killed

#### Investigation

1. **Check container memory usage vs. limit:**
   ```bash
   docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
   ```

2. **Check the configured memory limit:**
   ```bash
   docker inspect <container_name> --format='{{.HostConfig.Memory}}'
   ```

3. **Check for memory leaks in the application logs:**
   ```bash
   docker logs --tail 100 <container_name>
   ```

#### Resolution

- Increase the `mem_limit` in `docker-compose.yml` and restart:
  ```bash
  docker compose up -d <service_name>
  ```
- Restart the container to release leaked memory:
  ```bash
  docker restart <container_name>
  ```
- Investigate and fix the memory leak in the application

#### Escalation

If the container is a monitoring component (Prometheus, Loki), escalate to the PANOPTES team.

---

### ContainerRestarting

- **Severity**: Warning
- **Expression**: `increase(container_restart_count[10m]) > 3`
- **Duration**: 0 minutes (instant)
- **Auto-Remediation**: No

#### What

A container has restarted more than 3 times in the last 10 minutes. This indicates a crash loop.

#### Impact

- The service provided by this container is intermittently unavailable
- Each restart causes a brief outage
- The underlying issue will not resolve itself

#### Investigation

1. **Check container status:**
   ```bash
   docker ps -a | grep <container_name>
   ```

2. **Check container logs (including from previous runs):**
   ```bash
   docker logs --tail 100 <container_name>
   ```

3. **Check the exit code of the last crash:**
   ```bash
   docker inspect <container_name> --format='{{.State.ExitCode}}'
   # Exit code 137 = OOMKilled, 139 = Segfault, 1 = Application error
   ```

4. **Check if the container was OOMKilled:**
   ```bash
   docker inspect <container_name> --format='{{.State.OOMKilled}}'
   ```

#### Resolution

- Fix the root cause based on the exit code and logs
- If OOMKilled: Increase `mem_limit`
- If application error: Fix the configuration or code
- If dependency issue: Ensure dependent services are running
- Temporarily stop the container to prevent restart churn:
  ```bash
  docker stop <container_name>
  ```

#### Escalation

Escalate to the team responsible for the application running in the container. Provide the container name, exit code, and recent logs.

---

### ContainerKilled

- **Severity**: Critical
- **Expression**: `container_oom_events_total > 0`
- **Duration**: 0 minutes (instant)
- **Auto-Remediation**: No

#### What

A container was killed due to an out-of-memory event. Docker's OOM handler terminated the container because it exceeded its memory limit.

#### Impact

- The container is stopped and its service is unavailable
- Data in the container's writable layer may be lost
- Docker's restart policy will attempt to restart the container, but it may be killed again if the memory issue persists

#### Investigation

1. **Identify the killed container:**
   ```bash
   docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}"
   ```

2. **Confirm OOM kill:**
   ```bash
   docker inspect <container_name> --format='{{.State.OOMKilled}}'
   dmesg | grep -i "memory cgroup out of memory"
   ```

3. **Check the container's memory limit:**
   ```bash
   docker inspect <container_name> --format='{{.HostConfig.Memory}}'
   ```

#### Resolution

- Increase the container's `mem_limit` in `docker-compose.yml`:
  ```yaml
  services:
    service_name:
      mem_limit: 512m  # Increase from current value
  ```
- Apply the change:
  ```bash
  docker compose up -d <service_name>
  ```
- If the application has a memory leak, investigate and fix it

#### Escalation

Immediate escalation if the killed container is a critical monitoring component.

---

## Monitoring Stack Alerts

---

### PrometheusTargetDown

- **Severity**: Critical
- **Expression**: `up{job=~"prometheus|alertmanager|grafana|loki"} == 0`
- **Duration**: 3 minutes
- **Auto-Remediation**: No

#### What

A core monitoring stack component (Prometheus itself, Alertmanager, Grafana, or Loki) is unreachable.

#### Impact

- If Prometheus is down: All monitoring, alerting, and dashboards are non-functional
- If Alertmanager is down: Alerts fire but no notifications are sent
- If Grafana is down: Dashboards are unavailable (monitoring continues in background)
- If Loki is down: Log ingestion stops; new logs are lost

#### Investigation

1. **Check the Docker container status:**
   ```bash
   docker compose ps
   ```

2. **Check the logs of the failed component:**
   ```bash
   docker compose logs <component_name>
   ```

3. **Try to access the component's health endpoint directly:**
   ```bash
   curl http://localhost:9090/-/healthy    # Prometheus
   curl http://localhost:9093/-/healthy    # Alertmanager
   curl http://localhost:3000/api/health   # Grafana
   curl http://localhost:3100/ready        # Loki
   ```

#### Resolution

- Restart the failed component:
  ```bash
  docker compose restart <component_name>
  ```
- Check for resource exhaustion (memory, disk) on the host
- Check for configuration errors if the component fails to start

#### Escalation

If a core monitoring component cannot be restored, the entire monitoring pipeline is degraded. Escalate to the PANOPTES team immediately.

---

### PrometheusHighMemory

- **Severity**: Warning
- **Expression**: `process_resident_memory_bytes{job="prometheus"} / 536870912 * 100 > 80`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

Prometheus memory usage is above 80% of its 512 MB limit (approximately 410 MB).

#### Impact

- If memory continues to grow, Prometheus will be OOMKilled
- Queries may become slow or time out
- Alert evaluation may be delayed

#### Investigation

1. **Check Prometheus memory and TSDB stats:**
   ```bash
   curl http://localhost:9090/api/v1/status/tsdb | python3 -m json.tool
   ```

2. **Check the number of active time series:**
   ```bash
   curl -s http://localhost:9090/api/v1/label/__name__/values | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))"
   ```

3. **Check container memory:**
   ```bash
   docker stats --no-stream prometheus
   ```

#### Resolution

- Increase the `mem_limit` for Prometheus in `docker-compose.yml`
- Reduce the number of scrape targets or increase `scrape_interval`
- Reduce retention time: `--storage.tsdb.retention.time=7d`
- Drop unnecessary metrics using `metric_relabel_configs` in `prometheus.yml`

#### Escalation

If Prometheus memory continues to grow despite optimization, consider a capacity planning review with the infrastructure team.

---

### AlertmanagerNotificationFailed

- **Severity**: Critical
- **Expression**: `rate(alertmanager_notifications_failed_total[5m]) > 0`
- **Duration**: 1 minute
- **Auto-Remediation**: No

#### What

Alertmanager is failing to deliver notifications through one or more channels (Telegram, Email, or Webhook).

#### Impact

- Alert notifications are not being delivered
- Critical alerts may be missed by the operations team
- Auto-remediation may not trigger if webhook delivery is failing

#### Investigation

1. **Check Alertmanager logs for error details:**
   ```bash
   docker compose logs alertmanager | grep -i "error\|fail"
   ```

2. **Check which receiver is failing:**
   ```bash
   curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool
   ```

3. **Test Telegram bot:**
   ```bash
   curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
     -d "chat_id=${TELEGRAM_CHAT_ID}&text=PANOPTES test notification"
   ```

4. **Test webhook receiver:**
   ```bash
   curl http://localhost:5001/health
   ```

#### Resolution

- If Telegram bot token is invalid: Create a new bot via @BotFather and update `.env`
- If the webhook receiver is down: Restart it with `docker compose restart webhook-receiver`
- If network connectivity is the issue: Check firewall rules for outbound HTTPS

#### Escalation

This is a critical alert about the alerting system itself. If notifications cannot be restored, alert the team through an out-of-band channel (direct message, phone call).

---

### LokiIngestionRate

- **Severity**: Warning
- **Expression**: `rate(loki_distributor_lines_received_total[5m]) == 0`
- **Duration**: 5 minutes
- **Auto-Remediation**: No

#### What

Loki has not received any log lines in the last 5 minutes. The log pipeline is broken.

#### Impact

- New logs are not being collected or stored
- Log-based dashboards and searches will show no recent data
- Security-relevant logs (auth.log, SSH attempts) are not being captured

#### Investigation

1. **Check Promtail status:**
   ```bash
   docker compose logs promtail | tail -30
   ```

2. **Check if Promtail can reach Loki:**
   ```bash
   docker compose exec promtail wget -qO- http://loki:3100/ready
   ```

3. **Check Loki status:**
   ```bash
   curl http://localhost:3100/ready
   docker compose logs loki | tail -30
   ```

4. **Check if log source files exist:**
   ```bash
   ls -la /var/log/*.log
   ls -la /var/lib/docker/containers/
   ```

#### Resolution

- Restart Promtail:
  ```bash
  docker compose restart promtail
  ```
- Restart Loki if it is unhealthy:
  ```bash
  docker compose restart loki
  ```
- Check Loki disk usage (if `/loki` volume is full, ingestion stops):
  ```bash
  docker compose exec loki df -h /loki
  ```

#### Escalation

If the log pipeline cannot be restored, escalate to the PANOPTES team. Note that during the outage, logs are not being collected and may be lost.

---

### GrafanaDown

- **Severity**: Critical
- **Expression**: `up{job="grafana"} == 0`
- **Duration**: 2 minutes
- **Auto-Remediation**: No

#### What

Grafana is unreachable. Prometheus cannot scrape the Grafana health endpoint.

#### Impact

- Dashboards are unavailable
- Teams cannot view metrics or logs through the Grafana UI
- Monitoring continues in the background (Prometheus still collects and alerts)

#### Investigation

1. **Check Grafana container:**
   ```bash
   docker compose ps grafana
   docker compose logs grafana | tail -30
   ```

2. **Check if the port is accessible:**
   ```bash
   curl http://localhost:3000/api/health
   ```

3. **Check for common issues:**
   - Database locked: Grafana's SQLite database may be corrupted
   - Plugin installation failure: Check for plugin errors in logs
   - Memory limit: Check if the container was OOMKilled

#### Resolution

- Restart Grafana:
  ```bash
  docker compose restart grafana
  ```
- If the SQLite database is corrupted:
  ```bash
  docker compose stop grafana
  docker compose run --rm grafana grafana-cli admin data-migration
  docker compose start grafana
  ```
- If a plugin failed to install, check the `GF_INSTALL_PLUGINS` environment variable

#### Escalation

If Grafana cannot be restored, the team loses dashboard access. Metrics and alerts are unaffected. Escalate to the PANOPTES team.

---

## Predictive Alerts

---

### DiskWillFillIn4Hours

- **Severity**: Critical
- **Expression**: `predict_linear(node_filesystem_avail_bytes[1h], 4*3600) < 0`
- **Duration**: 15 minutes
- **Auto-Remediation**: No

#### What

Based on the trend over the last hour, a filesystem is predicted to fill completely within 4 hours. This is more urgent than DiskFillingUp (24-hour prediction).

#### Impact

- If no action is taken, the disk will fill within 4 hours
- All services writing to this filesystem will fail
- Databases, logging, and Docker operations will be disrupted

#### Investigation

1. **Identify which filesystem is filling:**
   ```bash
   ssh <target_host> "df -h"
   ```

2. **Determine the rate of growth:**
   Check the Grafana Node Detail dashboard for disk usage rate.

3. **Identify what is writing data at a high rate:**
   ```bash
   ssh <target_host> "iotop -oPa --delay=10 --iter=3"
   ```

4. **Check for runaway log writing:**
   ```bash
   ssh <target_host> "find /var/log -name '*.log' -mmin -60 -size +100M -ls"
   ```

#### Resolution

- Immediately free space using the most impactful cleanup:
  ```bash
  docker system prune -af
  journalctl --vacuum-size=200M
  find /var/log -name "*.log" -size +100M -exec truncate -s 0 {} +
  ```
- Identify and stop the process writing at a high rate
- If the fill rate is due to legitimate data growth, add disk capacity immediately

#### Escalation

This is a critical, time-sensitive alert. Escalate to the infrastructure team immediately with the timeline (4 hours) and current usage percentage. Request emergency disk expansion.

---

### MemoryLeakDetected

- **Severity**: Warning
- **Expression**: `deriv(process_resident_memory_bytes[1h]) > 1048576`
- **Duration**: 30 minutes
- **Auto-Remediation**: No

#### What

A process is showing a steady memory increase exceeding 1 MB per second over the last hour. This pattern strongly suggests a memory leak.

#### Impact

- The leaking process will eventually consume all available memory
- Will lead to OOM kills or HostOutOfMemory alert
- Other processes on the same host may be affected

#### Investigation

1. **Identify which process (job) is leaking:**
   The alert label `job` identifies the process. Check Grafana for the memory trend.

2. **Check the process memory over time:**
   In Grafana Explore, run:
   ```
   process_resident_memory_bytes{job="<job_name>"}
   ```

3. **Check the process heap (if available):**
   - For Prometheus: http://localhost:9090/debug/pprof/heap
   - For Go processes: `/debug/pprof/heap`
   - For Python processes: Use `tracemalloc` or `memory_profiler`

#### Resolution

- Restart the leaking process to immediately free memory:
  ```bash
  docker compose restart <service_name>
  ```
- File a bug report for the leaking application with the memory growth data
- Set up a cron job to periodically restart the service as a temporary workaround
- Implement memory limits (Docker `mem_limit`) to prevent the leak from affecting the host

#### Escalation

Escalate to the application team responsible for the leaking process. Provide the memory growth graph from Grafana and the timeframe.

---

## Common Troubleshooting Commands

### System Information

```bash
# System overview
uname -a
uptime
hostnamectl

# CPU info
nproc
lscpu

# Memory
free -h
vmstat 1 5

# Disk
df -h
iostat -x 1 5

# Network
ip addr show
ss -tuln
```

### Docker Commands

```bash
# Container status
docker compose ps
docker stats --no-stream

# Container logs
docker compose logs <service>
docker compose logs --tail 100 -f <service>

# Restart a service
docker compose restart <service>

# Rebuild and restart
docker compose up -d --build <service>

# Full reset (WARNING: destroys data)
docker compose down -v --remove-orphans
```

### Prometheus Queries (PromQL)

```bash
# Check all targets
curl http://localhost:9090/api/v1/targets | python3 -m json.tool

# Check firing alerts
curl http://localhost:9090/api/v1/alerts | python3 -m json.tool

# Run a query
curl -g 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool

# Check TSDB status
curl http://localhost:9090/api/v1/status/tsdb | python3 -m json.tool
```

### Alertmanager Queries

```bash
# Check current alerts
curl http://localhost:9093/api/v2/alerts | python3 -m json.tool

# Check silences
curl http://localhost:9093/api/v2/silences | python3 -m json.tool

# Check status
curl http://localhost:9093/api/v2/status | python3 -m json.tool
```

### Loki Queries (LogQL)

```bash
# Check available labels
curl http://localhost:3100/loki/api/v1/labels | python3 -m json.tool

# Query recent logs
curl -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="system"}' \
  --data-urlencode 'limit=10' | python3 -m json.tool
```

### Webhook Receiver Queries

```bash
# Health check
curl http://localhost:5001/health

# Remediation history
curl http://localhost:5001/history | python3 -m json.tool

# Active cooldowns
curl http://localhost:5001/cooldowns | python3 -m json.tool
```

---

## Log Locations

### On the PANOPTES Host

| Log | Location | Description |
|---|---|---|
| Prometheus | `docker compose logs prometheus` | Scrape errors, rule evaluation, TSDB |
| Alertmanager | `docker compose logs alertmanager` | Notification delivery, routing |
| Grafana | `docker compose logs grafana` | Dashboard rendering, plugin, auth |
| Loki | `docker compose logs loki` | Ingestion, compaction, storage |
| Promtail | `docker compose logs promtail` | Log collection, target discovery |
| Custom Exporter | `docker compose logs custom-exporter` | Collector errors, scrape failures |
| Webhook Receiver | `docker compose logs webhook-receiver` | Remediation execution, playbook output |

### On Monitored Hosts

| Log | Location | Description |
|---|---|---|
| System logs | `/var/log/syslog` or `/var/log/messages` | General system messages |
| Auth logs | `/var/log/auth.log` | SSH logins, sudo, authentication |
| Kernel logs | `dmesg` or `/var/log/kern.log` | OOM kills, hardware errors |
| Journal | `journalctl` | Systemd service logs |
| Docker logs | `/var/lib/docker/containers/` | Container stdout/stderr |

---

## Escalation Procedures

### Severity-Based Escalation

| Level | Criteria | Response Time | Action |
|---|---|---|---|
| P1 - Critical | Service outage, data loss risk, multiple systems affected | 15 minutes | Page on-call engineer, join incident channel |
| P2 - High | Single system degraded, critical alert firing | 1 hour | Notify on-call engineer via Telegram |
| P3 - Medium | Warning alert sustained, performance degradation | 4 hours | Create a ticket, investigate during business hours |
| P4 - Low | Informational, predictive alert | Next business day | Add to backlog, review in weekly ops meeting |

### Escalation Contacts

| Role | Responsibility | When to Contact |
|---|---|---|
| PANOPTES Team | Monitoring platform issues | Any monitoring stack alert |
| Infrastructure Team | Server hardware, networking, capacity | Host unreachable, hardware failure, capacity request |
| Application Team | Application-specific issues | Application crashes, memory leaks, configuration errors |
| Network Team | Network connectivity, firewall, DNS | Network errors, DNS issues, firewall changes |
| Security Team | Security incidents | Unauthorized SSH attempts, suspicious activity in logs |

### Incident Response Template

When escalating, include the following information:

```
Alert: <AlertName>
Severity: <critical/warning>
Affected Host: <instance>
Time Fired: <timestamp>
Current Value: <metric value>
Impact: <what is affected>
Investigation Summary: <what you checked and found>
Actions Taken: <what you did>
Help Needed: <specific request>
```
