param(
    [Parameter(Mandatory=$true)]
    [string]$ServerIP
)

$ErrorActionPreference = "Stop"

$ZabbixVersion = "7.4.0"
$DownloadUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/7.4/${ZabbixVersion}/zabbix_agent-${ZabbixVersion}-windows-amd64-openssl.msi"
$MsiPath = Join-Path $env:TEMP "zabbix_agent-${ZabbixVersion}-windows-amd64-openssl.msi"
$ZabbixConfDir = "C:\Program Files\Zabbix Agent"
$ZabbixConfFile = Join-Path $ZabbixConfDir "zabbix_agentd.conf"
$ZabbixConfDDir = Join-Path $ZabbixConfDir "zabbix_agentd.d"

Write-Host "============================================"
Write-Host "  UMAS Zabbix Agent Installation"
Write-Host "============================================"
Write-Host ""
Write-Host "  Zabbix Server IP: ${ServerIP}"
Write-Host ""

Write-Host ">>> Downloading Zabbix Agent v${ZabbixVersion}..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath -UseBasicParsing

Write-Host ">>> Installing Zabbix Agent..."
$MsiArgs = @(
    "/i"
    "`"$MsiPath`""
    "SERVER=${ServerIP}"
    "SERVERACTIVE=${ServerIP}"
    "HOSTNAME=$($env:COMPUTERNAME)"
    "/qn"
    "/norestart"
)
Start-Process -FilePath "msiexec.exe" -ArgumentList $MsiArgs -Wait -NoNewWindow

Write-Host ">>> Configuring UserParameters for AD health checks..."
if (-not (Test-Path $ZabbixConfDDir)) {
    New-Item -ItemType Directory -Path $ZabbixConfDDir -Force | Out-Null
}

$UserParamsContent = @"
UserParameter=ad.dcdiag.status,powershell -NoProfile -Command "try { `$result = dcdiag /q 2>&1; if (`$LASTEXITCODE -eq 0) { Write-Output 1 } else { Write-Output 0 } } catch { Write-Output 0 }"
UserParameter=ad.dcdiag.full,powershell -NoProfile -Command "dcdiag /v 2>&1 | Select-Object -First 100 | Out-String"
UserParameter=ad.replication.status,powershell -NoProfile -Command "try { `$result = repadmin /replsummary 2>&1; if (`$LASTEXITCODE -eq 0) { Write-Output 1 } else { Write-Output 0 } } catch { Write-Output 0 }"
UserParameter=ad.replication.summary,powershell -NoProfile -Command "repadmin /replsummary 2>&1 | Out-String"
"@

$UserParamsFile = Join-Path $ZabbixConfDDir "ad_userparameters.conf"
Set-Content -Path $UserParamsFile -Value $UserParamsContent -Encoding UTF8

$IncludeLine = "Include=${ZabbixConfDDir}\*.conf"
$ConfContent = Get-Content -Path $ZabbixConfFile -ErrorAction SilentlyContinue
if ($ConfContent -and ($ConfContent -notcontains $IncludeLine)) {
    Add-Content -Path $ZabbixConfFile -Value "`n${IncludeLine}"
    Write-Host "    Added Include directive to zabbix_agentd.conf"
}

Write-Host ">>> Creating Windows Firewall rule for TCP 10050..."
$ExistingRule = Get-NetFirewallRule -DisplayName "Zabbix Agent (TCP 10050)" -ErrorAction SilentlyContinue
if ($ExistingRule) {
    Write-Host "    Firewall rule already exists, updating..."
    Set-NetFirewallRule -DisplayName "Zabbix Agent (TCP 10050)" -Direction Inbound -Protocol TCP -LocalPort 10050 -Action Allow
} else {
    New-NetFirewallRule -DisplayName "Zabbix Agent (TCP 10050)" -Direction Inbound -Protocol TCP -LocalPort 10050 -Action Allow
}

Write-Host ">>> Starting Zabbix Agent service..."
Restart-Service -Name "Zabbix Agent" -ErrorAction SilentlyContinue
Set-Service -Name "Zabbix Agent" -StartupType Automatic

Write-Host ""
Write-Host "============================================"
Write-Host "  Zabbix Agent v${ZabbixVersion} installed"
Write-Host "  Server: ${ServerIP}"
Write-Host "  Hostname: $($env:COMPUTERNAME)"
Write-Host "  Listening on TCP 10050"
Write-Host "  AD UserParameters configured"
Write-Host "============================================"

Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue
