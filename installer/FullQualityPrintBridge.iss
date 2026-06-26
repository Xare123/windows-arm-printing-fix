; Inno Setup script - builds a clickable Setup.exe for non-technical users.
; Wizard: Welcome -> (info) -> Install -> runs setup-all.ps1 -> Finish.
; The Setup.exe is 32-bit and runs on Windows on ARM via emulation; it installs in ARM64 mode.

#define AppName "Full Quality Print Bridge"
#define AppVer  "1.1.0"
#define Pub     "clawmon-arm64 (community)"

[Setup]
AppId={{8F1C2A40-1C2B-4E7A-9A3D-PRINTBRIDGE01}
AppName={#AppName}
AppVersion={#AppVer}
AppPublisher={#Pub}
DefaultDirName={autopf}\FullQualityPrintBridge
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=C:\Claude\clawmon-arm64\dist
OutputBaseFilename=FullQualityPrintBridge-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=arm64 x64compatible
ArchitecturesInstallIn64BitMode=arm64 x64compatible
LicenseFile=C:\Claude\clawmon-arm64\bridge\LICENSE
SetupLogging=yes

[Files]
; the whole bridge toolkit (scripts + backend setup) ships inside the installer
Source: "C:\Claude\clawmon-arm64\bridge\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Messages]
WelcomeLabel2=This will add a normal "Full Quality (1200)" printer to Windows and set up a one‑time renderer (Linux/WSL running your printer's real driver) so your Brother prints at full resolution.%n%nNothing runs in the background — printing fires a one‑shot helper that then exits.

[Run]
; one elevated post-install step does everything: WSL backend + the Windows printer/event-task
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup-all.ps1"" -InstallDir ""{app}"" -PrinterIp ""{code:GetPrinterIp}"""; \
  StatusMsg: "Setting up the printer and the full‑quality renderer (first run downloads ~250 MB and can take several minutes)..."; \
  Flags: waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall-bridge.ps1"""; Flags: runhidden; RunOnceId: "RemoveBridge"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
{ Printer-selection page: a dropdown of already-installed printers (each auto-resolved
  to its IP / host from its port), plus an editable IP field as backup. The chosen IP
  becomes the CUPS queue device-uri (ipp://IP/ipp/print) at install. Blank = auto-detect. }
var
  PrinterPage: TWizardPage;
  PrinterCombo: TNewComboBox;
  IpEdit: TNewEdit;
  PrinterIps: TStringList;
  PrintersLoaded: Boolean;

procedure RefreshPrinterCombo;
var
  ps, tmpOut, scriptPath, line, nm, ip: String;
  lines: TArrayOfString;
  i, bar, rc: Integer;
begin
  PrinterCombo.Items.Clear;
  PrinterIps.Clear;
  PrinterCombo.Items.Add('(enter IP below, or leave blank to auto-detect)');
  PrinterIps.Add('');

  tmpOut := ExpandConstant('{tmp}\fqpb_printers.txt');
  scriptPath := ExpandConstant('{tmp}\fqpb_list.ps1');
  { Enumerate installed printers and resolve each to an IP/host from its port:
    IPP/http ports -> URL host; TCP/IP ports -> host address or IP in the port name.
    Virtual + the bridge's own printer are filtered out; WSD ports yield no IP (type it). }
  ps :=
    '$ErrorActionPreference="SilentlyContinue"' + #13#10 +
    '$r = foreach ($p in Get-Printer) {' + #13#10 +
    '  if ($p.Name -match "Print to PDF|Microsoft XPS|OneNote|Fax|Full Quality") { continue }' + #13#10 +
    '  $addr = ""' + #13#10 +
    '  if ($p.PortName -match "^https?://([^:/]+)") { $addr = $matches[1] }' + #13#10 +
    '  elseif ($p.PortName -match "(\d{1,3}(\.\d{1,3}){3})") { $addr = $matches[1] }' + #13#10 +
    '  else { $pp = Get-PrinterPort -Name $p.PortName -ErrorAction SilentlyContinue; if ($pp.PrinterHostAddress) { $addr = $pp.PrinterHostAddress } }' + #13#10 +
    '  "$($p.Name)|$addr"' + #13#10 +
    '}' + #13#10 +
    '$r | Out-File -Encoding ASCII "' + tmpOut + '"';
  SaveStringToFile(scriptPath, ps, False);
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + scriptPath + '"',
       '', SW_HIDE, ewWaitUntilTerminated, rc);

  if LoadStringsFromFile(tmpOut, lines) then
  begin
    for i := 0 to GetArrayLength(lines) - 1 do
    begin
      line := Trim(lines[i]);
      if line = '' then Continue;
      bar := Pos('|', line);
      if bar = 0 then Continue;
      nm := Copy(line, 1, bar - 1);
      ip := Copy(line, bar + 1, Length(line));
      if ip <> '' then
        PrinterCombo.Items.Add(nm + '    [' + ip + ']')
      else
        PrinterCombo.Items.Add(nm + '    [no IP found - type it below]');
      PrinterIps.Add(ip);
    end;
  end;
  PrinterCombo.ItemIndex := 0;
end;

procedure PrinterComboChange(Sender: TObject);
var idx: Integer;
begin
  idx := PrinterCombo.ItemIndex;
  if (idx >= 0) and (idx < PrinterIps.Count) then
    if PrinterIps[idx] <> '' then
      IpEdit.Text := PrinterIps[idx];
end;

procedure InitializeWizard;
var
  lbl: TNewStaticText;
begin
  PrinterIps := TStringList.Create;
  PrintersLoaded := False;

  PrinterPage := CreateCustomPage(wpWelcome, 'Choose your printer',
    'Pick an installed printer, or type its IP. Works with any AirPrint / IPP printer - virtually all modern Brother network printers, and most other brands.');

  lbl := TNewStaticText.Create(PrinterPage);
  lbl.Parent := PrinterPage.Surface;
  lbl.Top := ScaleY(4);
  lbl.Caption := 'Installed printer:';

  PrinterCombo := TNewComboBox.Create(PrinterPage);
  PrinterCombo.Parent := PrinterPage.Surface;
  PrinterCombo.Style := csDropDownList;
  PrinterCombo.Left := 0;
  PrinterCombo.Top := lbl.Top + lbl.Height + ScaleY(4);
  PrinterCombo.Width := PrinterPage.SurfaceWidth;
  PrinterCombo.OnChange := @PrinterComboChange;

  lbl := TNewStaticText.Create(PrinterPage);
  lbl.Parent := PrinterPage.Surface;
  lbl.AutoSize := False;
  lbl.WordWrap := True;
  lbl.Left := 0;
  lbl.Top := PrinterCombo.Top + PrinterCombo.Height + ScaleY(16);
  lbl.Width := PrinterPage.SurfaceWidth;
  lbl.Height := ScaleY(34);
  lbl.Caption := 'IP address (auto-filled from your choice above; edit it, or type one for a printer that is not in the list). Leave blank to try auto-detecting an AirPrint printer.';

  IpEdit := TNewEdit.Create(PrinterPage);
  IpEdit.Parent := PrinterPage.Surface;
  IpEdit.Left := 0;
  IpEdit.Top := lbl.Top + lbl.Height + ScaleY(4);
  IpEdit.Width := PrinterPage.SurfaceWidth;
  IpEdit.Text := '';
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = PrinterPage.ID) and (not PrintersLoaded) then
  begin
    RefreshPrinterCombo;
    PrintersLoaded := True;
  end;
end;

function GetPrinterIp(Param: String): String;
begin
  Result := Trim(IpEdit.Text);
end;
