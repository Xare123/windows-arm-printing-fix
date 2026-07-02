# setup-all.ps1 - one-shot orchestrator the installer runs (elevated):
#   0) WSL config (mirrored networking + memory reclaim),
#   1) ensure a WSL Ubuntu distro,
#   2) CUPS driverless queue (the renderer),
#   2.5) the NATIVE full-color printer (front-end + Windows printer),
#   3) the classic popup bridge (fallback).
# Idempotent: re-running skips anything already done.
param(
  [string]$InstallDir = $PSScriptRoot,
  [string]$Distro     = 'Ubuntu-2404',
  [string]$PrinterIp  = ''    # blank = auto-discover the AirPrint printer on the LAN (ippfind)
)
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$logDir = "$env:ProgramData\ArmPrintBridge"; New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'setup-all.log'
function Log($m){ $s = "$(Get-Date -Format s)  $m"; Write-Host $s; $s | Add-Content -Path $log }
function DistroExists { ((& wsl.exe -l -q) -replace "`0","" | ForEach-Object { $_.Trim() }) -contains $Distro }
# Deterministic Windows->WSL path transform. (Calling `wsl wslpath` from PowerShell
# mangles backslashes and returns empty - verified - so never rely on it here.)
function ToWsl([string]$p) { '/mnt/' + $p.Substring(0,1).ToLower() + ($p.Substring(2) -replace '\\','/') }

Log "=== Full Quality Print Bridge - setup-all ==="

# ---- preflight: WSL must exist ----------------------------------------------
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Log "ERROR: WSL is not installed. Run 'wsl --install' in an admin terminal, reboot, then re-run this setup."
  exit 1
}
& wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
  Log "ERROR: WSL is present but not operational (try 'wsl --install' / 'wsl --update', reboot, re-run)."
  exit 1
}

# ---- 0) WSL2 mirrored networking + memory reclaim ---------------------------
# Default WSL2 NAT stalls large print transfers to a LAN printer (big/photo pages
# print ~1/5 then fade to blank). Mirrored networking puts WSL directly on the LAN,
# like the host/Mac, so large URF transfers complete.
$wslcfg = "$env:USERPROFILE\.wslconfig"
$curCfg = if (Test-Path $wslcfg) { Get-Content $wslcfg -Raw } else { "" }
if ($curCfg -notmatch 'networkingMode\s*=\s*mirrored') {
  Log "enabling WSL2 mirrored networking (fixes large-page transfer stalls)..."
  if ($curCfg -match '(?m)^\s*\[wsl2\]') { $newCfg = $curCfg -replace '(?m)^\s*\[wsl2\][^\r\n]*', "[wsl2]`r`nnetworkingMode=mirrored" }
  else { $newCfg = ($curCfg.TrimEnd() + "`r`n[wsl2]`r`nnetworkingMode=mirrored").Trim() + "`r`n" }
  Set-Content -Path $wslcfg -Value $newCfg -Encoding ASCII
  & wsl.exe --shutdown 2>&1 | Out-Null
  $curCfg = Get-Content $wslcfg -Raw
}
if ($curCfg -notmatch 'autoMemoryReclaim') {
  Log "enabling WSL2 autoMemoryReclaim (resident WSL returns idle RAM)..."
  $newCfg = $curCfg -replace '(\[wsl2\])', "`$1`r`nautoMemoryReclaim=gradual"
  Set-Content -Path $wslcfg -Value $newCfg -Encoding ASCII
}

# ---- 1) WSL renderer distro --------------------------------------------------
if (DistroExists) {
  Log "WSL distro '$Distro' present."
} else {
  $d = "$env:LOCALAPPDATA\ArmPrintBridge\wsl"; New-Item -ItemType Directory -Force -Path $d | Out-Null
  $xz = Join-Path $d 'rootfs.tar.xz'; $tar = Join-Path $d 'rootfs.tar'
  $bundled = Join-Path $InstallDir 'backend\rootfs.tar.xz'   # if the installer bundled it
  if (Test-Path $bundled) { Copy-Item $bundled $xz -Force; Log "using bundled rootfs" }
  elseif (-not (Test-Path $xz) -and -not (Test-Path $tar)) {
    Log "downloading Ubuntu 24.04 ARM64 rootfs (~212 MB)..."
    Invoke-WebRequest 'https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz' -OutFile $xz -UseBasicParsing
  }
  Log "importing '$Distro'..."
  $src = if (Test-Path $tar) { $tar } else { $xz }
  & wsl.exe --import $Distro (Join-Path $d $Distro) $src --version 2 2>&1 | ForEach-Object { Log "  $_" }
  if (-not (DistroExists)) {
    Log "compressed import not accepted; decompressing then importing..."
    # NOTE: on stock Windows, Get-Command python resolves to the 0-byte Microsoft
    # Store alias stub which exits 9009 doing nothing - validate before trusting it.
    $py = (Get-Command python -EA SilentlyContinue).Source
    if (-not $py) { $py = (Get-Command py -EA SilentlyContinue).Source }
    $pyWorks = $false
    if ($py) { $probe = & $py -c "print('ok')" 2>$null; $pyWorks = ($probe -eq 'ok') }
    if ($pyWorks) {
      & $py -c "import lzma,shutil;shutil.copyfileobj(lzma.open(r'$xz'),open(r'$tar','wb'))"
    } else {
      & tar.exe -xJf $xz -C $d 2>&1 | ForEach-Object { Log "  $_" }
    }
    if (-not (Test-Path $tar)) { Log "ERROR: could not decompress the rootfs (no working python, tar.exe failed)."; exit 1 }
    & wsl.exe --import $Distro (Join-Path $d $Distro) $tar --version 2 2>&1 | ForEach-Object { Log "  $_" }
  }
}
if (-not (DistroExists)) { Log "ERROR: WSL distro setup failed."; exit 1 }

# ---- 2) CUPS driverless queue inside WSL (skip if it already exists) ---------
$haveQueue = ((& wsl.exe -d $Distro -u root -- bash -lc "lpstat -v FullQuality 2>/dev/null") -match 'FullQuality')
if ($haveQueue) {
  Log "CUPS queue already configured in WSL."
} else {
  Log "configuring WSL (systemd + CUPS driverless queue)..."
  # Append-only: NEVER truncate /etc/wsl.conf (a user's existing [boot] command
  # or other settings must survive).
  & wsl.exe -d $Distro -u root -- bash -lc 'touch /etc/wsl.conf; grep -q "systemd=true" /etc/wsl.conf || printf "[boot]\nsystemd=true\n" >> /etc/wsl.conf; grep -q "generateResolvConf" /etc/wsl.conf || printf "[network]\ngenerateResolvConf=true\n" >> /etc/wsl.conf' 2>&1 | Out-Null
  & wsl.exe --shutdown 2>&1 | Out-Null
  $wslsh = ToWsl (Join-Path $InstallDir 'backend\setup-airprint-backend.sh')
  $backendOut = @(& wsl.exe -d $Distro -u root -- bash -lc "tr -d '\r' < '$wslsh' > /root/b.sh && bash /root/b.sh $PrinterIp" 2>&1)
  $backendOut | ForEach-Object { Log "  $_" }
  if (-not ($backendOut -match 'AIRPRINT-BACKEND-DONE')) {
    Log "ERROR: the CUPS queue could not be set up (is the printer ON and reachable?). Stopping."
    exit 1
  }
}

# ---- 2.5) NATIVE full-color printer (recommended) ----------------------------
# A normal Windows printer with the native dialog (quality/duplex/grayscale)
# whose jobs are rendered by CUPS for vivid color. See backend/setup-native-frontend.sh.
Log "installing the native front-end in WSL..."
foreach ($f in 'setup-native-frontend.sh','nativeprint.sh','ippeve-supervisor.sh') {
  $src = ToWsl (Join-Path $InstallDir ("backend\" + $f))
  & wsl.exe -d $Distro -u root -- bash -lc "tr -d '\r' < '$src' > /root/$f" 2>&1 | Out-Null
}
$feOut = @(& wsl.exe -d $Distro -u root -- bash -lc "bash /root/setup-native-frontend.sh FullQuality 60631 'Full Color Printer' 1" 2>&1)
$feOut | ForEach-Object { Log "  $_" }
if (-not ($feOut -match 'NATIVE-FRONTEND-DONE')) {
  Log "ERROR: the native front-end did not start (see lines above). Stopping."
  exit 1
}

Log "wiring the native Windows printer (firewall + keep-alive + printer)..."
& (Join-Path $InstallDir 'setup-native-printer.ps1') -Distro $Distro -Unattended 2>&1 | ForEach-Object { Log "  $_" }
if ($LASTEXITCODE -ne 0) { Log "ERROR: the native Windows printer could not be added. Stopping."; exit 1 }

# ---- 3) OPTIONAL: the classic popup bridge ("Full Quality (1200)") ----------
# Kept for compatibility; the native printer above is the recommended path.
Log "installing the popup-bridge printer + event-driven forwarder..."
& (Join-Path $InstallDir 'install-bridge.ps1') -Unattended 2>&1 | ForEach-Object { Log "  $_" }

Log "=== setup-all DONE ==="
