# bridge — a native, on‑demand full‑quality printer (no custom driver, no signing)

A **normal printer** in every app's Print dialog that prints at full quality by handing each job to **CUPS in WSL**, which renders to the printer's native **AirPrint (URF)** format — the same path macOS uses, for the same rich color. It uses Windows' **own signed** *Microsoft Print To PDF* driver, so there's **no driver to sign** and no signing wall.

## Runs nothing in the background

The flow is **event‑driven**:

```
You print → inbox Print‑to‑PDF writes the job to a file
          → Windows logs a "document printed" event
          → Task Scheduler launches forward.ps1 ONCE
          → a quick Draft/Normal/Best popup → wsl armprint → CUPS prints → forward.ps1 exits
```

No service, no watcher, no tray icon. The only always‑on components are the Windows **spooler** and **Task Scheduler**, already running for every printer. WSL starts only for that job and shuts itself down after.

## Install — clickable

Run **`FullQualityPrintBridge-Setup.exe`** (from the GitHub Release) and follow the wizard. It:
1. creates a WSL Ubuntu distro with CUPS (first run downloads ~250 MB),
2. **auto‑discovers your AirPrint printer** (or you can pass its IP),
3. enables **WSL2 mirrored networking** (so large pages don't stall),
4. adds the **"Full Quality (1200)"** printer + the print‑event task.

Then print to **"Full Quality (1200)"** from any app and pick a quality on the popup.

## Install — manual / scriptable

```powershell
# 1) WSL backend — inside your Ubuntu distro, as root:
#      bash setup-airprint-backend.sh                 # auto-discovers the printer
#      bash setup-airprint-backend.sh 192.168.1.50    # ...or give its IP
# 2) Windows side (self-elevates for the printer + event task):
pwsh -ExecutionPolicy Bypass -File .\install-bridge.ps1
```

`setup-all.ps1` runs all of the above in one shot (it's what the installer calls); it also sets WSL2 mirrored networking.

## Quality

The popup's **Draft / Normal / Best** maps to CUPS `cupsPrintQuality` **Draft / Normal / High**. "Best" engages the printer's full droplet mode — see the [repo root README](../README.md) on why **Best**, not a "1200 dpi" setting, is the real lever (the printer only accepts ≤600‑dpi input on any OS).

## Point it at a different backend

`config.json` (`forwardExe` / `forwardArgs`) controls what each job is handed to. Default:
`wsl -d {DISTRO} -u root -- /usr/local/bin/armprint {QUALITY} {WSLFILE}`. Placeholders substituted per job:
- `{DISTRO}` → your `wslDistro`
- `{QUALITY}` → Draft/Normal/High from the popup
- `{WSLFILE}` → the job's path inside WSL (auto‑translated)
- `{FILE}` → the job's Windows path (use for `curl`/network backends)

See `config.example.json` for `curl`/`lpr` examples (e.g. forwarding straight to a CUPS/Mac/Pi over the network).

## Verify / troubleshoot
- Backend directly: `wsl -d Ubuntu-2404 -u root -- /usr/local/bin/armprint High /etc/hostname`
- Watch the log: `Get-Content C:\ProgramData\ArmPrintBridge\bridge.log -Wait`
- **Test page:** print **`TESTPAGE.pdf`** — a frame + 4 corner marks (truncation check), a 6–24 pt text ladder (sharpness), and color swatches + gradient + grayscale ramp (color/transfer). Regenerate with `backend/maketestpage.sh`.

## Notes / limits
- One document at a time — the Local Port writes one fixed file, so a flurry of simultaneous prints can race. Fine for normal use.
- `forward.ps1` runs as **you** (so it can reach *your* WSL distro), event‑triggered, only while you're logged on.
- The quality popup needs an interactive session; if it can't show, it falls back to **Best**.
- Uninstall with `uninstall-bridge.ps1` (removes the printer, port, task, and `C:\ProgramData\ArmPrintBridge`).

## License
MIT — see `LICENSE`. (The clawmon component at the repo root is GPL‑2.)
