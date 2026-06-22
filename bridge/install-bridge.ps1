# install-bridge.ps1 - sets up a normal "Full Quality (1200)" printer that forwards each
# job to your real renderer, EVENT-DRIVEN (no background service/watcher/daemon).
# Self-elevates. Run once. Edit ..\bridge\config.example.json first if your backend differs.
param(
  [string]$PrinterName = 'Full Quality (1200)',
  [string]$TaskName    = 'ArmPrintBridge',
  [string]$Driver      = 'Microsoft Print To PDF',
  [switch]$Unattended
)
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  $fwd = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  if ($Unattended) { $fwd += '-Unattended' }
  Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $fwd
  Write-Host "Re-launching elevated (approve UAC)..."; exit
}

$src     = $PSScriptRoot
$cfgFile = Join-Path $src 'config.json'
if (-not (Test-Path $cfgFile)) { Copy-Item (Join-Path $src 'config.example.json') $cfgFile }
$cfg     = Get-Content -Raw $cfgFile | ConvertFrom-Json
$install = $cfg.installDir

Write-Host "== staging into $install =="
New-Item -ItemType Directory -Force -Path $install,$cfg.workDir | Out-Null
Copy-Item (Join-Path $src 'forward.ps1') (Join-Path $install 'forward.ps1') -Force
Copy-Item (Join-Path $src 'QualityPicker.ps1') (Join-Path $install 'QualityPicker.ps1') -Force
Copy-Item $cfgFile (Join-Path $install 'config.json') -Force
$fwd = Join-Path $install 'forward.ps1'
$cfgInstalled = Join-Path $install 'config.json'

Write-Host "== Local Port (writes each job to $($cfg.jobFile)) =="
if (-not (Get-PrinterPort -Name $cfg.jobFile -ErrorAction SilentlyContinue)) { Add-PrinterPort -Name $cfg.jobFile }

Write-Host "== printer '$PrinterName' ($Driver) =="
Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue | Remove-Printer -ErrorAction SilentlyContinue
Add-Printer -Name $PrinterName -DriverName $Driver -PortName $cfg.jobFile
Write-Host "  created: $((Get-Printer -Name $PrinterName).Name)"

Write-Host "== enable the print 'document printed' event log =="
& wevtutil.exe sl Microsoft-Windows-PrintService/Operational /e:true 2>&1 | Out-Null

Write-Host "== register EVENT-DRIVEN task '$TaskName' (fires on print, runs forward.ps1 once, exits) =="
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute (Get-Command pwsh -ErrorAction SilentlyContinue).Source `
          -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$fwd`" -ConfigPath `"$cfgInstalled`""
if (-not $action.Execute) { $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$fwd`" -ConfigPath `"$cfgInstalled`"" }
# event trigger: PrintService/Operational, EventID 307 = "document printed"
$tc = Get-CimClass -Namespace ROOT/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskEventTrigger
$trigger = New-CimInstance -CimClass $tc -ClientOnly
$trigger.Enabled = $true
$trigger.Subscription = '<QueryList><Query Id="0" Path="Microsoft-Windows-PrintService/Operational"><Select Path="Microsoft-Windows-PrintService/Operational">*[System[(EventID=307)]]</Select></Query></QueryList>'
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances Queue -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host ""
Write-Host "Done. '$PrinterName' is now in your Print dialog."
Write-Host "Nothing runs in the background - the print event launches forward.ps1 for one job, then it exits."
Write-Host "Make sure your backend works first, e.g.:  wsl -d $($cfg.wslDistro) -u root -- lp -d <queue> --version"
Write-Host "Logs: $(Join-Path $install 'bridge.log')"
if (-not $Unattended) { Write-Host "Press Enter to close..."; [void](Read-Host) }
