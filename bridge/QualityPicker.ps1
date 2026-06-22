# QualityPicker.ps1 - tiny per-job print-quality chooser for the AirPrint bridge.
# Shows Draft / Normal / Best and auto-confirms Best after a few seconds. Writes the
# cupsPrintQuality keyword (Draft | Normal | High) to stdout.
# Must run STA so WinForms is reliable:  powershell.exe -STA -File QualityPicker.ps1
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:result = 'High'   # default if the user does nothing / dialog fails to show
$script:secs   = 4        # auto-confirm countdown (seconds)

$f = New-Object System.Windows.Forms.Form
$f.Text            = 'Print Quality'
$f.FormBorderStyle = 'FixedDialog'
$f.StartPosition   = 'CenterScreen'
$f.TopMost         = $true
$f.MinimizeBox     = $false
$f.MaximizeBox     = $false
$f.ShowInTaskbar   = $true
$f.ClientSize      = New-Object System.Drawing.Size(372,156)
$f.BackColor       = [System.Drawing.Color]::White

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text     = 'Quality for this print:'
$lbl.AutoSize = $true
$lbl.Location = New-Object System.Drawing.Point(18,16)
$lbl.Font     = New-Object System.Drawing.Font('Segoe UI',10)
$f.Controls.Add($lbl)

function New-QButton([string]$text,[string]$val,[int]$x,[bool]$isDefault){
  $b = New-Object System.Windows.Forms.Button
  $b.Text     = $text
  $b.Size     = New-Object System.Drawing.Size(104,48)
  $b.Location = New-Object System.Drawing.Point($x,46)
  $b.Font     = New-Object System.Drawing.Font('Segoe UI',10)
  $b.Add_Click({ $script:result = $val; $f.Close() }.GetNewClosure())
  if ($isDefault) { $f.AcceptButton = $b; $b.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold) }
  $f.Controls.Add($b)
}
New-QButton 'Draft'  'Draft'  18  $false
New-QButton 'Normal' 'Normal' 132 $false
New-QButton 'Best'   'High'   246 $true

$cd = New-Object System.Windows.Forms.Label
$cd.AutoSize  = $true
$cd.Location  = New-Object System.Drawing.Point(18,112)
$cd.ForeColor = [System.Drawing.Color]::Gray
$cd.Font      = New-Object System.Drawing.Font('Segoe UI',8)
$cd.Text      = "Best in $script:secs s..."
$f.Controls.Add($cd)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
  $script:secs--
  if ($script:secs -le 0) { $timer.Stop(); $f.Close() } else { $cd.Text = "Best in $script:secs s..." }
})
$timer.Start()

[void]$f.ShowDialog()
$timer.Stop()
Write-Output $script:result
