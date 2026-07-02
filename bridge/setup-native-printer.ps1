# setup-native-printer.ps1 - Windows side of the NATIVE full-color printer.
# Adds a normal Windows printer (inbox Microsoft IPP Class Driver) that prints
# through the WSL CUPS pipeline for vivid, Mac-quality color. Native dialog:
# quality, duplex (long/short edge), grayscale, copies, paper size all work.
#
# Run AFTER the WSL side is set up (setup-airprint-backend.sh + setup-native-frontend.sh),
# or let setup-all.ps1 orchestrate everything.
#
# What it does (idempotent):
#   1. Hyper-V firewall rule so Windows can reach the WSL front-end port (needs admin).
#   2. A hidden logon keep-alive so the WSL distro (and the front-end) is always up.
#   3. autoMemoryReclaim=gradual in .wslconfig so resident WSL gives idle RAM back.
#   4. Adds the printer against http://127.0.0.1:<port>/ipp/print.
param(
  [string]$PrinterName = 'Full Color Printer',
  [string]$Distro     = 'Ubuntu-2404',
  [int]$Port          = 60631,
  [switch]$Unattended
)
$ErrorActionPreference = 'Continue'
function Log($m) { Write-Host "  $m" }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---- 1) Hyper-V firewall rule (inbound to the WSL VM is blocked by default) ----
$ruleName = "WSL-IPPEVE-$Port"
$have = Get-NetFirewallHyperVRule -Name $ruleName -ErrorAction SilentlyContinue
if (-not $have) {
  if ($admin) {
    New-NetFirewallHyperVRule -Name $ruleName -DisplayName 'WSL native print front-end' `
      -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' `
      -Protocol TCP -LocalPorts $Port | Out-Null
    Log "Hyper-V firewall rule '$ruleName' added."
  } else {
    Log "elevating once to add the Hyper-V firewall rule..."
    $cmd = "New-NetFirewallHyperVRule -Name $ruleName -DisplayName 'WSL native print front-end' -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts $Port | Out-Null"
    Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoProfile','-Command',$cmd)
  }
  # A NEW Hyper-V rule only applies after the WSL VM restarts (observed: probes
  # fail until then). The keep-alive below boots the distro right back up, and
  # /etc/wsl.conf [boot] command restarts the front-end automatically.
  Log "restarting WSL so the firewall rule takes effect..."
  & wsl.exe --shutdown 2>&1 | Out-Null
  Start-Sleep -Seconds 3
} else { Log "Hyper-V firewall rule '$ruleName' already present." }

# ---- 2) logon keep-alive (hidden; keeps the distro + front-end up) ----
$startupDir = if ($admin) { [Environment]::GetFolderPath('CommonStartup') } else { [Environment]::GetFolderPath('Startup') }
$vbs = Join-Path $startupDir 'WSL-PrintBackend.vbs'
@"
' Keeps the WSL distro (CUPS + native print front-end) alive, hidden. No admin needed.
CreateObject("Wscript.Shell").Run "wsl.exe -d $Distro -u root -- sleep infinity", 0, False
"@ | Set-Content -Path $vbs -Encoding ASCII
Log "logon keep-alive: $vbs"

# ---- 3) .wslconfig: reclaim idle WSL memory (safe with mirrored networking) ----
$wslcfg = "$env:USERPROFILE\.wslconfig"
$cur = if (Test-Path $wslcfg) { Get-Content $wslcfg -Raw } else { "[wsl2]`r`n" }
if ($cur -notmatch 'autoMemoryReclaim') {
  if ($cur -match '(?m)^\s*\[wsl2\]') { $cur = $cur -replace '(\[wsl2\])', "`$1`r`nautoMemoryReclaim=gradual" }
  else { $cur = "[wsl2]`r`nautoMemoryReclaim=gradual`r`n" + $cur }
  Set-Content -Path $wslcfg -Value $cur -Encoding ASCII
  Log ".wslconfig: autoMemoryReclaim=gradual added."
}

# ---- 4) make sure the front-end is reachable, then add the printer ----
Start-Process -WindowStyle Hidden wscript.exe -ArgumentList "`"$vbs`""   # boot distro now if down
$up = $false
for ($i = 0; $i -lt 30; $i++) {
  & curl.exe -s -m 2 -o NUL http://127.0.0.1:$Port/ 2>$null
  if ($LASTEXITCODE -eq 0) { $up = $true; break }
  if ($i -eq 5) { & wsl.exe -d $Distro -u root -- /bin/sh -c 'nohup setsid /usr/local/bin/ippeve-supervisor >/dev/null 2>&1 &' 2>$null }
  Start-Sleep -Seconds 2
}
if (-not $up) { Log "!! front-end not reachable on 127.0.0.1:$Port - run setup-native-frontend.sh in WSL first."; exit 1 }

$existing = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if (-not $existing) {
  try {
    Add-Printer -Name $PrinterName -DriverName 'Microsoft IPP Class Driver' -PortName "http://127.0.0.1:$Port/ipp/print" -ErrorAction Stop
    Log "printer '$PrinterName' added."
  } catch {
    Log "!! Add-Printer failed: $($_.Exception.Message)"
    exit 1
  }
} else { Log "printer '$PrinterName' already present." }
Log "DONE - print to '$PrinterName' from any app."
exit 0
