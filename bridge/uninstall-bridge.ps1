# uninstall-bridge.ps1 - removes what install-bridge.ps1 AND setup-native-printer.ps1
# created (both printers, task, port, firewall rules, keep-alive). Self-elevates.
# The WSL distro is left in place (remove yourself with: wsl --unregister Ubuntu-2404).
param(
  [string]$PrinterName = 'Full Quality (1200)',
  [string]$NativePrinterName = 'Full Color Printer',
  [string]$TaskName = 'ArmPrintBridge',
  [switch]$Unattended
)
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  $extra = @(); if ($Unattended) { $extra += '-Unattended' }
  Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $extra)
  exit
}
$cfgFile = Join-Path $PSScriptRoot 'config.json'
$cfg = if (Test-Path $cfgFile) { Get-Content -Raw $cfgFile | ConvertFrom-Json } else { $null }

# popup bridge pieces
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "removed task: $TaskName"
Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue | Remove-Printer -ErrorAction SilentlyContinue
Write-Host "removed printer: $PrinterName"
if ($cfg) {
  if (Get-PrinterPort -Name $cfg.jobFile -ErrorAction SilentlyContinue) { Remove-PrinterPort -Name $cfg.jobFile -ErrorAction SilentlyContinue; Write-Host "removed port: $($cfg.jobFile)" }
  if ($cfg.installDir -and (Test-Path $cfg.installDir)) { Remove-Item -Recurse -Force $cfg.installDir -ErrorAction SilentlyContinue; Write-Host "removed $($cfg.installDir)" }
}

# native printer pieces
Get-Printer -Name $NativePrinterName -ErrorAction SilentlyContinue | Remove-Printer -ErrorAction SilentlyContinue
Write-Host "removed printer: $NativePrinterName"
foreach ($dir in @([Environment]::GetFolderPath('CommonStartup'), [Environment]::GetFolderPath('Startup'))) {
  $vbs = Join-Path $dir 'WSL-PrintBackend.vbs'
  if (Test-Path $vbs) { Remove-Item $vbs -Force -ErrorAction SilentlyContinue; Write-Host "removed keep-alive: $vbs" }
}
Get-NetFirewallHyperVRule -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'WSL-IPPEVE-*' -or $_.Name -eq 'WSL-CUPS-IPP' } |
  ForEach-Object { Remove-NetFirewallHyperVRule -Name $_.Name -ErrorAction SilentlyContinue; Write-Host "removed firewall rule: $($_.Name)" }

Write-Host "Done. The WSL distro is untouched (remove with: wsl --unregister <distro>)."
Write-Host "(The print event log is left enabled - harmless; disable with: wevtutil sl Microsoft-Windows-PrintService/Operational /e:false)"
if (-not $Unattended) { Write-Host "Press Enter to close..."; [void](Read-Host) }
