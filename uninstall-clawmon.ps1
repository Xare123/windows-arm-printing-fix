# clawmon ARM64 - UNREGISTER the monitor and remove its DLLs. Self-elevates. Fully reverses install.
$build = 'C:\Claude\clawmon-arm64\build\arm64'
$log   = 'C:\Claude\clawmon-arm64\uninstall-log.txt'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  Write-Host "Re-launching elevated (approve UAC)..."; exit
}
"=== clawmon uninstall  $(Get-Date -Format s) ===" | Set-Content -Path $log
"--- regmon.exe -d (DeleteMonitor) ---" | Tee-Object -FilePath $log -Append
& "$build\regmon.exe" -d 2>&1 | Tee-Object -FilePath $log -Append
"regmon -d exit: $LASTEXITCODE" | Tee-Object -FilePath $log -Append
try { Restart-Service Spooler -Force; "spooler restarted" | Tee-Object -FilePath $log -Append } catch { "spooler restart err: $_" | Tee-Object -FilePath $log -Append }
Start-Sleep -Seconds 1
Remove-Item "$env:WINDIR\System32\clawmon.dll"   -Force -ErrorAction SilentlyContinue
Remove-Item "$env:WINDIR\System32\clawmonui.dll" -Force -ErrorAction SilentlyContinue
"removed System32 DLLs" | Tee-Object -FilePath $log -Append
"=== DONE ===" | Tee-Object -FilePath $log -Append
Write-Host "Done. Press Enter to close..."; [void](Read-Host)
