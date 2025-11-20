$ErrorActionPreference = "Stop"

$ExporterVersion = "0.31.2"
$DownloadUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v${ExporterVersion}/windows_exporter-${ExporterVersion}-amd64.msi"
$MsiPath = Join-Path $env:TEMP "windows_exporter-${ExporterVersion}-amd64.msi"
$Collectors = "ad,dns,dhcp,cpu,memory,net,logical_disk,os,service,system,time,cache,process"

Write-Host "============================================"
Write-Host "  PANOPTES Windows Exporter Installation"
Write-Host "============================================"
Write-Host ""

Write-Host ">>> Downloading windows_exporter v${ExporterVersion}..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath -UseBasicParsing

Write-Host ">>> Installing windows_exporter with collectors: ${Collectors}..."
$MsiArgs = @(
    "/i"
    "`"$MsiPath`""
    "ENABLED_COLLECTORS=${Collectors}"
    "/qn"
    "/norestart"
)
Start-Process -FilePath "msiexec.exe" -ArgumentList $MsiArgs -Wait -NoNewWindow

Write-Host ">>> Creating Windows Firewall rule for TCP 9182..."
$ExistingRule = Get-NetFirewallRule -DisplayName "Windows Exporter (TCP 9182)" -ErrorAction SilentlyContinue
if ($ExistingRule) {
    Write-Host "    Firewall rule already exists, updating..."
    Set-NetFirewallRule -DisplayName "Windows Exporter (TCP 9182)" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow
} else {
    New-NetFirewallRule -DisplayName "Windows Exporter (TCP 9182)" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow
}

Write-Host ">>> Starting windows_exporter service..."
Start-Service -Name "windows_exporter" -ErrorAction SilentlyContinue
Set-Service -Name "windows_exporter" -StartupType Automatic

Write-Host ">>> Verifying metrics endpoint..."
Start-Sleep -Seconds 5
try {
    $Response = Invoke-WebRequest -Uri "http://localhost:9182/metrics" -UseBasicParsing -TimeoutSec 10
    Write-Host "    Metrics endpoint returned HTTP $($Response.StatusCode)"
} catch {
    Write-Host "    WARNING: Could not reach metrics endpoint. Service may still be starting."
}

Write-Host ""
Write-Host "============================================"
Write-Host "  Windows Exporter v${ExporterVersion} installed"
Write-Host "  Metrics available at http://localhost:9182/metrics"
Write-Host "  Enabled collectors: ${Collectors}"
Write-Host "============================================"

Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue
