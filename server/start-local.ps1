$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $root "config.local.json"
$config = Get-Content $configPath | ConvertFrom-Json

$webPort = [int]$config.services.web.port
$apiPort = [int]$config.services.api.port
$aria2RpcUrl = [string]$config.downloaders.aria2.rpc_url
$downloadDir = [string]$config.downloaders.aria2.download_dir
$aria2Secret = [string]$config.downloaders.aria2.secret
$aria2Exe = Join-Path $root "aria2-1.37.0-win-64bit-build1\aria2c.exe"

function Stop-PortListeners {
  param([int[]]$Ports)

  $pattern = (($Ports | ForEach-Object { [regex]::Escape(":$_") }) -join "|")
  $lines = netstat -ano | Select-String $pattern
  $pids = $lines | ForEach-Object {
    $parts = ($_ -split "\s+") | Where-Object { $_ }
    $parts[-1]
  } | Where-Object { $_ -match "^\d+$" -and $_ -ne "0" } | Sort-Object -Unique

  foreach ($procId in $pids) {
    Stop-Process -Id ([int]$procId) -Force -ErrorAction SilentlyContinue
  }
}

function Wait-ForHttp {
  param(
    [string]$Url,
    [int]$Seconds = 15
  )

  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    try {
      Invoke-WebRequest -UseBasicParsing $Url | Out-Null
      return $true
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  return $false
}

Write-Host "Cleaning stale listeners..."
Stop-PortListeners -Ports @($webPort, $apiPort, 6800)

Write-Host "Preparing download directory..."
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

if (-not (Test-Path $aria2Exe)) {
  throw "aria2c.exe was not found at $aria2Exe"
}

$aria2Args = @(
  "--enable-rpc",
  "--rpc-listen-all=false",
  "--rpc-listen-port=6800",
  "--auto-file-renaming=true",
  "--dir=$downloadDir"
)

if ($aria2Secret) {
  $aria2Args += "--rpc-secret=$aria2Secret"
}

Write-Host "Starting aria2..."
Start-Process -FilePath $aria2Exe -ArgumentList $aria2Args -WorkingDirectory (Split-Path $aria2Exe -Parent) -WindowStyle Minimized | Out-Null

Write-Host "Starting app..."
Start-Process -FilePath "python" -ArgumentList "app.py" -WorkingDirectory $root -WindowStyle Minimized | Out-Null

Write-Host "Waiting for services..."
$webReady = Wait-ForHttp -Url "http://127.0.0.1:$webPort/"
$apiReady = Wait-ForHttp -Url "http://127.0.0.1:$apiPort/api/v1/health"

if (-not $webReady -or -not $apiReady) {
  throw "The app did not become ready on http://127.0.0.1:$webPort/ and http://127.0.0.1:$apiPort/api/v1/health"
}

Write-Host "Opening local dashboard..."
Start-Process "http://127.0.0.1:$webPort/"

try {
  $system = Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$apiPort/api/v1/system" | Select-Object -ExpandProperty Content | ConvertFrom-Json
  Write-Host ""
  Write-Host "LAN IP: $($system.system.preferredLanIp)"
  Write-Host "LAN API: $($system.system.api.lanUrl)"
} catch {
  Write-Host ""
  Write-Host "The app started, but system info could not be fetched."
}
