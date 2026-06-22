# clawmon ARM64 - register the print port monitor (Gate 1 test).
# Requires admin; self-elevates via UAC. Logs everything to install-log.txt.
$build = 'C:\Claude\clawmon-arm64\build\arm64'
$log   = 'C:\Claude\clawmon-arm64\install-log.txt'

# --- self-elevate if not admin ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  $host_exe = (Get-Process -Id $PID).Path
  Start-Process -FilePath $host_exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  Write-Host "Re-launching elevated (approve the UAC prompt)..."
  exit
}

function Log($m) { $m | Tee-Object -FilePath $log -Append }

"=== clawmon ARM64 monitor install  $(Get-Date -Format s) ===" | Set-Content -Path $log
Log "running as admin: $admin"

# 1) copy the monitor DLL into System32 (where the spooler loads port monitors)
try {
  Copy-Item "$build\clawmon.dll" "$env:WINDIR\System32\clawmon.dll" -Force
  Log "OK: copied clawmon.dll -> System32"
  if (Test-Path "$build\clawmonui.dll") { Copy-Item "$build\clawmonui.dll" "$env:WINDIR\System32\clawmonui.dll" -Force; Log "OK: copied clawmonui.dll -> System32" }
} catch { Log "ERROR copying DLL: $_" }

# 2) register the monitor. AddMonitor LOADS the DLL and calls InitializePrintMonitor2
#    inside spoolsv.exe -- this is the make-or-break test.
Log "--- regmon.exe -r (AddMonitor) ---"
& "$build\regmon.exe" -r 2>&1 | Tee-Object -FilePath $log -Append
Log "regmon exit code: $LASTEXITCODE"

# 3) verify: is the monitor now registered?
Log "--- registered print monitors (registry) ---"
try {
  (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors' -ErrorAction Stop).PSChildName | ForEach-Object { Log "  $_" }
} catch { Log "ERROR reading monitors key: $_" }

Log "--- regmon.exe -l (EnumMonitors) ---"
& "$build\regmon.exe" -l 2>&1 | Tee-Object -FilePath $log -Append

# 4) spooler still healthy?
Log "--- spooler service status ---"
Log ("  Spooler: " + (Get-Service -Name Spooler).Status)
Log "=== DONE ==="
Write-Host ""
Write-Host "Done. Results written to $log"
Write-Host "Press Enter to close..."
[void](Read-Host)
