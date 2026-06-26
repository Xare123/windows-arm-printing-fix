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
1. **asks which printer to use** — pick it from a **dropdown of installed printers**, or enter its **IP address** (any AirPrint/IPP printer works; leave blank to try auto‑detect),
2. creates a WSL Ubuntu distro with CUPS (first run downloads ~250 MB),
3. enables **WSL2 mirrored networking** (so large pages don't stall),
4. adds the **"Full Quality (1200)"** printer + the print‑event task, pointed at your printer.

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

## Which printer it targets — and changing it later

Targeting is set **once at install**: the WSL CUPS queue (`FullQuality`) is created with
`device-uri = ipp://<your-printer-IP>/ipp/print`. Every job goes to that queue, so it always
hits that one printer. The `armprint` helper just runs `lp -d FullQuality` — the queue's URI is what aims it.

- **You give the printer's IP at install** (the wizard asks; the manual command takes it as an argument). mDNS auto‑detect is *attempted* when you leave it blank, but it's unreliable inside WSL2 — **entering the IP is recommended.**
- **Any AirPrint / IPP‑Everywhere printer works** — Brother or otherwise. Nothing here is model‑specific (generic `everywhere` driver + standard PWG options).
- **Multiple printers?** Pass the specific IP; auto‑detect otherwise just grabs the first it sees.
- **Switch printers later (no reinstall)** — repoint the queue inside WSL:
  ```bash
  wsl -d Ubuntu-2404 -u root -- lpadmin -p FullQuality -E -v ipp://NEW.PRINTER.IP/ipp/print
  ```

## Quality & sides

When you print, a small popup lets you pick **Quality** (Draft / Normal / **Best**) and **Sides** (**Double‑sided** / Single‑sided) per job. It defaults to **Best + Double‑sided** and auto‑confirms after a few seconds, so the common case is zero clicks. Sides maps to the IPP `sides` attribute (`two-sided-long-edge` / `one-sided`); the printer's auto‑duplex does the rest.

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
- **Prints one page then the queue jams ("Waiting for job to complete")?** Many AirPrint printers (this Brother included) print the page but never tell CUPS the job finished, so the queue wedges and later jobs stop coming out. The backend sets `?waitjob=false` on the queue URI so jobs complete after the data is sent; to apply it by hand: `wsl -d Ubuntu-2404 -u root -- lpadmin -p FullQuality -v "ipp://YOUR.PRINTER.IP/ipp/print?waitjob=false"`.
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
