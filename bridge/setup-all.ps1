# setup-all.ps1 - one-shot orchestrator the installer runs (elevated):
#   1) ensure a WSL Ubuntu distro with the vendor's real driver (the renderer),
#   2) install the Windows-side printer + event-driven forwarder.
# Idempotent: re-running skips anything already done. No background process is created.
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

Log "=== Full Quality Print Bridge - setup-all ==="

# ---- 0) WSL2 mirrored networking -------------------------------------------------
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
}

# ---- 1) WSL renderer backend ------------------------------------------------
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
    $py = (Get-Command python -EA SilentlyContinue).Source; if (-not $py) { $py = (Get-Command py -EA SilentlyContinue).Source }
    if ($py) { & $py -c "import lzma,shutil;shutil.copyfileobj(lzma.open(r'$xz'),open(r'$tar','wb'))" }
    else     { & tar.exe -xJf $xz -C $d; if (Test-Path (Join-Path $d 'rootfs.tar')) {} }
    & wsl.exe --import $Distro (Join-Path $d $Distro) $tar --version 2 2>&1 | ForEach-Object { Log "  $_" }
  }
}
if (-not (DistroExists)) { Log "ERROR: WSL distro setup failed."; exit 1 }

# ---- 2) CUPS AirPrint queue inside WSL (skip if it already exists) -----------
$haveQueue = ((& wsl.exe -d $Distro -u root -- bash -lc "lpstat -v FullQuality 2>/dev/null") -match 'FullQuality')
if ($haveQueue) {
  Log "AirPrint queue already configured in WSL."
} else {
  Log "configuring WSL (systemd + CUPS AirPrint queue)..."
  & wsl.exe -d $Distro -u root -- bash -lc 'printf "[boot]\nsystemd=true\n[network]\ngenerateResolvConf=true\n" >/etc/wsl.conf' 2>&1 | Out-Null
  & wsl.exe --shutdown 2>&1 | Out-Null
  $sh = Join-Path $InstallDir 'backend\setup-airprint-backend.sh'
  $wslsh = (& wsl.exe -d $Distro wslpath "$sh") 2>$null
  & wsl.exe -d $Distro -u root -- bash -lc "tr -d '\r' < '$wslsh' > /root/b.sh && bash /root/b.sh $PrinterIp" 2>&1 | ForEach-Object { Log "  $_" }
}

# ---- 3) Windows printer + event-driven forwarder ----------------------------
Log "installing the Windows printer + event-driven forwarder..."
& (Join-Path $InstallDir 'install-bridge.ps1') -Unattended 2>&1 | ForEach-Object { Log "  $_" }

Log "=== setup-all DONE ==="
