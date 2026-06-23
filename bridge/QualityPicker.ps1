# QualityPicker.ps1 - per-job print options for the AirPrint bridge.
# Shows Quality (Draft/Normal/Best) + Sides (Double/Single); auto-confirms the
# defaults (Best + Double-sided) after a few seconds. Writes ONE line to stdout:
#   "<quality>|<sides>"   e.g.  "High|two-sided-long-edge"   or  "Draft|one-sided"
# Must run STA so WinForms is reliable:  powershell.exe -STA -File QualityPicker.ps1
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:secs = 5

$f = New-Object System.Windows.Forms.Form
$f.Text = 'Print Options'
$f.FormBorderStyle = 'FixedDialog'
$f.StartPosition = 'CenterScreen'
$f.TopMost = $true; $f.MinimizeBox = $false; $f.MaximizeBox = $false; $f.ShowInTaskbar = $true
$f.ClientSize = New-Object System.Drawing.Size(384, 210)
$f.BackColor = [System.Drawing.Color]::White
$font = New-Object System.Drawing.Font('Segoe UI', 10)

function New-RB([string]$text, [int]$x, [int]$y, [bool]$checked) {
  $r = New-Object System.Windows.Forms.RadioButton
  $r.Text = $text
  $r.Location = New-Object System.Drawing.Point($x, $y)
  $r.Size = New-Object System.Drawing.Size(150, 24)
  $r.Font = $font
  $r.Checked = $checked
  return $r
}

$gq = New-Object System.Windows.Forms.GroupBox
$gq.Text = 'Quality'; $gq.Font = $font
$gq.Location = New-Object System.Drawing.Point(16, 10)
$gq.Size = New-Object System.Drawing.Size(352, 56)
$qDraft  = New-RB 'Draft'  14 22 $false
$qNormal = New-RB 'Normal' 110 22 $false
$qBest   = New-RB 'Best'   232 22 $true
$gq.Controls.AddRange(@($qDraft, $qNormal, $qBest))

$gs = New-Object System.Windows.Forms.GroupBox
$gs.Text = 'Sides'; $gs.Font = $font
$gs.Location = New-Object System.Drawing.Point(16, 74)
$gs.Size = New-Object System.Drawing.Size(352, 56)
$sDouble = New-RB 'Double-sided' 14 22 $true
$sSingle = New-RB 'Single-sided' 190 22 $false
$gs.Controls.AddRange(@($sDouble, $sSingle))

$ok = New-Object System.Windows.Forms.Button
$ok.Text = 'Print'
$ok.Location = New-Object System.Drawing.Point(268, 150)
$ok.Size = New-Object System.Drawing.Size(100, 34)
$ok.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$ok.Add_Click({ $f.Close() })
$f.AcceptButton = $ok

$cd = New-Object System.Windows.Forms.Label
$cd.AutoSize = $true
$cd.Location = New-Object System.Drawing.Point(18, 160)
$cd.ForeColor = [System.Drawing.Color]::Gray
$cd.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$cd.Text = "Auto-print in $script:secs s (defaults shown)..."

$f.Controls.AddRange(@($gq, $gs, $ok, $cd))

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
  $script:secs--
  if ($script:secs -le 0) { $timer.Stop(); $f.Close() } else { $cd.Text = "Auto-print in $script:secs s (defaults shown)..." }
})
$timer.Start()

[void]$f.ShowDialog()
$timer.Stop()

$q = if ($qDraft.Checked) { 'Draft' } elseif ($qNormal.Checked) { 'Normal' } else { 'High' }
$s = if ($sSingle.Checked) { 'one-sided' } else { 'two-sided-long-edge' }
Write-Output "$q|$s"
