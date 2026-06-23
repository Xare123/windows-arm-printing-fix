# forward.ps1 - ONE-SHOT. Launched by the print-event Scheduled Task when a job lands,
# runs for a second or two, and exits. This is NOT a background service/watcher.
#
# It claims the captured PDF, asks the user the print quality for THIS job (one printer,
# per-job choice), hands the file to the configured renderer (the WSL CUPS AirPrint
# queue via the `armprint` helper), and cleans up.
param([string]$ConfigPath = "$PSScriptRoot\config.json")

$ErrorActionPreference = 'Continue'
try { $cfg = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json } catch { exit 0 }
$log = Join-Path $cfg.installDir 'bridge.log'
function Log($m) { try { "$(Get-Date -Format s)  $m" | Add-Content -Path $log } catch {} }

# nothing to do unless our printer actually produced a job
if (-not (Test-Path $cfg.jobFile) -or (Get-Item $cfg.jobFile).Length -eq 0) { exit 0 }

# claim the file so two near-simultaneous events can't double-send it
New-Item -ItemType Directory -Force -Path $cfg.workDir | Out-Null
$claim = Join-Path $cfg.workDir ("job_{0}.pdf" -f ([guid]::NewGuid().ToString('N')))
try { Move-Item -LiteralPath $cfg.jobFile -Destination $claim -Force -ErrorAction Stop }
catch { exit 0 }   # someone else already grabbed it
Log "claimed $claim ($((Get-Item $claim).Length) bytes)"

# Ask the user the quality for THIS job (Draft/Normal/Best; auto-Best after a few seconds).
# Run the picker in a separate STA Windows PowerShell so WinForms is reliable. This never
# blocks printing: any failure or timeout falls back to High (Best).
$quality = 'High'; $sides = 'two-sided-long-edge'
$picker = Join-Path $cfg.installDir 'QualityPicker.ps1'
if (Test-Path $picker) {
  try {
    $psexe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $psexe)) { $psexe = 'powershell.exe' }
    $out  = & $psexe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File $picker 2>$null
    $pick = $out | Where-Object { $_ -match '^(Draft|Normal|High)\|(one-sided|two-sided-long-edge|two-sided-short-edge)$' } | Select-Object -Last 1
    if ($pick) { $p = $pick.Split('|'); $quality = $p[0]; $sides = $p[1] }
  } catch { Log "picker error: $($_.Exception.Message)" }
}
Log "quality = $quality, sides = $sides"

# Build the argument list, substituting {DISTRO}, {QUALITY}, {FILE} (Windows path),
# and {WSLFILE} (Linux path).
$wslFile = $null
$argList = @()
foreach ($a in $cfg.forwardArgs) {
  $x = [string]$a
  $x = $x.Replace('{DISTRO}', [string]$cfg.wslDistro)
  $x = $x.Replace('{QUALITY}', $quality)
  $x = $x.Replace('{SIDES}', $sides)
  $x = $x.Replace('{FILE}', $claim)
  if ($x.Contains('{WSLFILE}')) {
    # Convert C:\dir\file -> /mnt/c/dir/file in-process (calling `wsl wslpath` here
    # mangled the backslashes and returned empty, which broke the lp command).
    if (-not $wslFile) { $wslFile = '/mnt/' + $claim.Substring(0,1).ToLower() + ($claim.Substring(2) -replace '\\','/') }
    $x = $x.Replace('{WSLFILE}', $wslFile)
  }
  $argList += $x
}

Log "running: $($cfg.forwardExe) $($argList -join ' ')"
try {
  & $cfg.forwardExe @argList 2>&1 | ForEach-Object { Log "  $_" }
  Log "exit code: $LASTEXITCODE"
} catch { Log "ERROR: $($_.Exception.Message)" }

Remove-Item -LiteralPath $claim -Force -ErrorAction SilentlyContinue
