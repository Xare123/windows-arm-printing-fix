; Inno Setup script - builds a clickable Setup.exe for non-technical users.
; Wizard: Welcome -> (info) -> Install -> runs setup-all.ps1 -> Finish.
; The Setup.exe is 32-bit and runs on Windows on ARM via emulation; it installs in ARM64 mode.

#define AppName "Full Quality Print Bridge"
#define AppVer  "1.0.0"
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
ArchitecturesAllowed=arm64 x64
ArchitecturesInstallIn64BitMode=arm64 x64
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
{ Wizard page that asks which printer to target. The IP becomes the CUPS queue's
  device-uri (ipp://IP/ipp/print) at install time. Blank = try auto-detect. }
var
  PrinterPage: TInputQueryWizardPage;

procedure InitializeWizard;
begin
  PrinterPage := CreateInputQueryPage(wpWelcome,
    'Choose your printer',
    'Which printer should print at full quality?',
    'Enter your printer''s IP address (recommended). You can find it on the printer''s screen under Settings > Network > WLAN Status, or in your router''s device list. Any AirPrint / IPP-capable printer works.' + #13#10#13#10 +
    'Leave blank to try auto-detecting an AirPrint printer on your network (may not work on all setups).');
  PrinterPage.Add('Printer IP address:', False);
end;

function GetPrinterIp(Param: String): String;
begin
  Result := Trim(PrinterPage.Values[0]);
end;
