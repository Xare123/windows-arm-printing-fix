# uninstall-bridge.ps1 - removes everything install-bridge.ps1 created. Self-elevates.
param([string]$PrinterName = 'Full Quality (1200)', [string]$TaskName = 'ArmPrintBridge')
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  exit
}
$cfgFile = Join-Path $PSScriptRoot 'config.json'
$cfg = if (Test-Path $cfgFile) { Get-Content -Raw $cfgFile | ConvertFrom-Json } else { $null }

Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "removed task: $TaskName"
Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue | Remove-Printer -ErrorAction SilentlyContinue
Write-Host "removed printer: $PrinterName"
if ($cfg) {
  if (Get-PrinterPort -Name $cfg.jobFile -ErrorAction SilentlyContinue) { Remove-PrinterPort -Name $cfg.jobFile -ErrorAction SilentlyContinue; Write-Host "removed port: $($cfg.jobFile)" }
  if ($cfg.installDir -and (Test-Path $cfg.installDir)) { Remove-Item -Recurse -Force $cfg.installDir -ErrorAction SilentlyContinue; Write-Host "removed $($cfg.installDir)" }
}
Write-Host "Done (the print event log is left enabled - harmless; disable with: wevtutil sl Microsoft-Windows-PrintService/Operational /e:false)"
Write-Host "Press Enter to close..."; [void](Read-Host)
