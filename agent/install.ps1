$ErrorActionPreference = "Stop"

param(
    [string]$Server,
    [string]$Key,
    [string]$Tenant
)

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "============================================"
Write-Host "  PANOPTES Windows Agent Installation"
Write-Host "============================================"
Write-Host ""

if (-not $Server) { $Server = Read-Host "Enter Panoptes server URL (e.g. https://panoptes.example.com:8080)" }
if (-not $Key)    { $Key    = Read-Host "Enter Panoptes API key" }
if (-not $Tenant) { $Tenant = Read-Host "Enter tenant name" }

$AlloyDir = "C:\Program Files\Grafana Alloy"
$AlloyConfig = Join-Path $AlloyDir "config-windows.alloy"
$AlloyEnv = Join-Path $AlloyDir "env.txt"
$AlloyBin = Join-Path $AlloyDir "alloy.exe"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ExistingExporter = Get-Service -Name "windows_exporter" -ErrorAction SilentlyContinue
if (-not $ExistingExporter) {
    Write-Host ">>> Installing windows_exporter..."
    $ExporterVersion = "0.31.2"
    $MsiUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v${ExporterVersion}/windows_exporter-${ExporterVersion}-amd64.msi"
    $MsiPath = Join-Path $env:TEMP "windows_exporter.msi"
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing
    $Collectors = "ad,dns,dhcp,cpu,memory,net,logical_disk,os,service,system,time,cache,process"
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$MsiPath`"", "ENABLED_COLLECTORS=${Collectors}", "/qn", "/norestart" -Wait -NoNewWindow
    New-NetFirewallRule -DisplayName "Windows Exporter (TCP 9182)" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow -ErrorAction SilentlyContinue
    Start-Service -Name "windows_exporter" -ErrorAction SilentlyContinue
    Set-Service -Name "windows_exporter" -StartupType Automatic
    Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue
    Write-Host "    windows_exporter v${ExporterVersion} installed and started."
} else {
    Write-Host ">>> windows_exporter is already installed."
}

Write-Host ">>> Downloading Grafana Alloy..."
$AlloyRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/grafana/alloy/releases/latest" -UseBasicParsing
$AlloyVersion = $AlloyRelease.tag_name -replace "^v", ""
$AlloyZipUrl = "https://github.com/grafana/alloy/releases/download/v${AlloyVersion}/alloy-windows-amd64.zip"
$AlloyZip = Join-Path $env:TEMP "alloy-windows.zip"
Invoke-WebRequest -Uri $AlloyZipUrl -OutFile $AlloyZip -UseBasicParsing

Write-Host ">>> Installing Alloy v${AlloyVersion}..."
if (-not (Test-Path $AlloyDir)) { New-Item -ItemType Directory -Path $AlloyDir -Force | Out-Null }
Expand-Archive -Path $AlloyZip -DestinationPath $AlloyDir -Force
if (-not (Test-Path $AlloyBin)) {
    $ExtractedExe = Get-ChildItem -Path $AlloyDir -Filter "alloy*.exe" -Recurse | Select-Object -First 1
    if ($ExtractedExe) { Move-Item -Path $ExtractedExe.FullName -Destination $AlloyBin -Force }
}
Remove-Item -Path $AlloyZip -Force -ErrorAction SilentlyContinue

Write-Host ">>> Writing Alloy configuration..."
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigSource = Join-Path $ScriptDir "config-windows.alloy"
if (Test-Path $ConfigSource) {
    Copy-Item -Path $ConfigSource -Destination $AlloyConfig -Force
} else {
    Write-Host "    WARNING: config-windows.alloy not found at ${ConfigSource}. Download it manually." -ForegroundColor Yellow
}

Write-Host ">>> Writing environment file..."
@"
PANOPTES_SERVER_URL=${Server}
PANOPTES_API_KEY=${Key}
PANOPTES_TENANT=${Tenant}
HOSTNAME=$($env:COMPUTERNAME)
"@ | Set-Content -Path $AlloyEnv -Encoding UTF8

$Acl = Get-Acl $AlloyEnv
$Acl.SetAccessRuleProtection($true, $false)
$AdminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "FullControl", "Allow")
$SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "Allow")
$Acl.AddAccessRule($AdminRule)
$Acl.AddAccessRule($SystemRule)
Set-Acl -Path $AlloyEnv -AclObject $Acl

Write-Host ">>> Creating Alloy Windows service..."
$ExistingService = Get-Service -Name "GrafanaAlloy" -ErrorAction SilentlyContinue
if ($ExistingService) {
    Stop-Service -Name "GrafanaAlloy" -Force -ErrorAction SilentlyContinue
    sc.exe delete GrafanaAlloy | Out-Null
    Start-Sleep -Seconds 2
}

$EnvPairs = @(
    "PANOPTES_SERVER_URL=${Server}",
    "PANOPTES_API_KEY=${Key}",
    "PANOPTES_TENANT=${Tenant}",
    "HOSTNAME=$($env:COMPUTERNAME)"
)
foreach ($pair in $EnvPairs) {
    $parts = $pair -split "=", 2
    [System.Environment]::SetEnvironmentVariable($parts[0], $parts[1], "Machine")
}

New-Service -Name "GrafanaAlloy" `
    -BinaryPathName "`"$AlloyBin`" run `"$AlloyConfig`"" `
    -DisplayName "Grafana Alloy (Panoptes Agent)" `
    -Description "Pushes metrics and logs to the Panoptes monitoring platform" `
    -StartupType Automatic | Out-Null

Write-Host ">>> Opening firewall for Alloy health port (TCP 12345)..."
New-NetFirewallRule -DisplayName "Grafana Alloy Health (TCP 12345)" -Direction Inbound -Protocol TCP -LocalPort 12345 -Action Allow -ErrorAction SilentlyContinue | Out-Null

Write-Host ">>> Starting Alloy service..."
Start-Service -Name "GrafanaAlloy"

Write-Host ""
Write-Host "============================================"
Write-Host "  Panoptes Windows Agent Installed"
Write-Host "  Alloy v${AlloyVersion} => ${Server}"
Write-Host "  Tenant: ${Tenant}"
Write-Host "  Config: ${AlloyConfig}"
Write-Host "  Service: GrafanaAlloy"
Write-Host "============================================"
Write-Host ""

Get-Service -Name "GrafanaAlloy" | Format-Table -Property Name, Status, StartType -AutoSize
