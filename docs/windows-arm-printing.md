# Full‑quality printing on Windows‑on‑ARM — what works, what doesn't, and why

> **⚠️ Update (2026): the recommended solution changed — see the [root README](../README.md).**
> These notes chase *the vendor's Brother driver under WSL* and call it "1200 dpi." Later testing corrected two things:
> 1. **"1200 × 600 dpi" is the printer's droplet (output) resolution, not an input.** It accepts only **≤ 600 dpi** input on every interface (verified via `ipptool`) — your Mac sends ≤600 too. **Best/High quality** is the real lever, on any OS.
> 2. **The Brother proprietary‑driver path is actually *worse*:** its CUPS filter hard‑codes Ghostscript to 300 dpi (visible glyph "drift") and its closed converter segfaults above the 300‑dpi page size. The shipped solution now uses the printer's **native AirPrint / IPP‑Everywhere path via CUPS** (`bridge/`), rendering with poppler → URF at the printer's true maximum — the same path macOS uses.
>
> The driver‑loading and **signing walls** documented below are still accurate and worth reading; only the "use the Brother driver for 1200" conclusion is superseded.

Field notes from getting a **Brother MFC‑J4335DW** to print at native **1200 dpi** from a Snapdragon Windows 11 laptop (ARM64, build 26220). Most of it generalises to any printer whose vendor ships no ARM64 driver. Written so the next person doesn't have to rediscover the walls.

## The core wall
- **Vendors often ship no ARM64 print driver.** Brother's official answer for Windows‑on‑ARM is "use the built‑in driver." That driver is Microsoft's **IPP Class Driver**, which for this printer caps at **600 dpi**.
- **You can't run the vendor's x86/x64 driver.** Windows‑on‑ARM emulates whole x64 *applications*, but a v3 print driver's DLLs must load **inside** `spoolsv.exe` / `PrintIsolationHost.exe`, which are **native ARM64** processes — and an ARM64 process cannot load x64 code. There is no per‑DLL emulation. This is the root cause and there is no setting that changes it.
- **Only the vendor's proprietary rasterizer makes full‑quality output**, and it exists only for x86‑Windows, macOS, and Linux. Generic drivers (IPP, Mopria, Gutenprint, vendor "class" drivers) can't reproduce it. (Gutenprint also barely covers Brother inkjets, and there's no Gutenprint *Windows* driver anyway.)

**Conclusion:** the real driver has to run on Linux/Mac, and Windows must hand the job there. Everything below is about *how* to hand it over.

## What actually produces 1200 dpi: the vendor driver under Linux (WSL)
Verified working — a test page physically printed at Fine/1200 from the ARM laptop, no Mac involved:

1. **WSL2 Ubuntu (ARM64).** `wsl --install` kept aborting mid‑download here; the reliable workaround was to `curl` the Ubuntu 24.04 ARM64 root filesystem (`cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz`), decompress with Python `lzma`, and `wsl --import` it. Enable systemd via `/etc/wsl.conf`.
2. **CUPS + the vendor's Linux driver.** Install `cups cups-filters ghostscript qemu-user-static`. Brother's driver for this model (`mfcj4335dwpdrv-3.5.0-1.i386.deb` from download.brother.com) ships **both x86_64 and i686** binaries; on ARM64 run the **x86_64** ones under **`qemu-x86_64-static`**. They have no `NEEDED` libs, so you only need amd64 glibc — add an `amd64` multiarch source pointed at `archive.ubuntu.com` (the `ports` mirror has no amd64) and `apt install libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64`, then invoke with `QEMU_LD_PREFIX=/`.
3. Install the driver manually (its `postinst` arch‑detect fails on aarch64): copy the tree to `/opt/brother/...`, make small shell wrappers at the flat binary paths that `exec qemu-x86_64-static .../x86_64/<bin>`, symlink the CUPS filter, drop the PPD.
4. `lpadmin -p MFCJ4335DW -E -v socket://<printer-ip>:9100 -P <ppd>`. Quality is the PPD's `BRResolution` = Draft/Normal/**Fine** (Fine ≈ the 1200‑class mode).
5. Print from Windows by sending a PDF/PostScript to that queue: `wsl -d Ubuntu -u root -- lp -d MFCJ4335DW -o BRResolution=Fine <file>`. CUPS + the Brother filter rasterize at full quality.

The job arrives as **vector** (PDF/PS) and CUPS re‑rasterizes it — so quality is **not** capped at whatever Windows rendered. That's the whole trick.

## Getting a *normal Windows printer* to feed that queue
This is where it gets subtle. You need the Windows print job to reach the Linux queue as **vector** (PDF/PS), not a pre‑rasterized 600‑dpi bitmap.

### What works: inbox Print‑to‑PDF on an inbox port → a forwarder  (← this repo's `bridge/`)
- Make a printer with the inbox, **already‑signed** *Microsoft Print To PDF* driver on a **Local Port** (a file). It writes a clean PDF, no "Save As" prompt.
- Forward that PDF to the Linux queue. To avoid a background watcher, trigger the forward from the **PrintService "document printed" event (ID 307)** via a Scheduled Task — event‑driven, nothing resident.
- No custom driver, no signing. **This is the practical answer.**

### What *doesn't* work (so you don't waste days on it)
- **`Add-Printer` (the CIM cmdlet) fails on third‑party monitor ports** with a misleading `ERROR_INVALID_PRINTER_NAME` (1801). Works fine on inbox ports. Use raw `AddPrinterW` for custom ports.
- **v4 "package" drivers (incl. *Microsoft Print To PDF*, the MS‑XPS / Brother‑Jpeg class drivers) refuse to bind to a third‑party (e.g. clawmon) port** — `AddPrinter` *and* `Set-Printer -PortName` both fail with 1801. A **v3** driver binds fine (verified with the inbox Zebra ZDesigner driver). So a clawmon‑style port needs a **v3** driver.
- **A `PORT_INFO_2` with `fPortType = 0` isn't enough** for the modern ARM spooler to bind a printer; set `PORT_TYPE_WRITE` (necessary, not sufficient — see the v4 issue above).
- **You can't install a custom v3 driver without a Microsoft‑trusted signature.** `pnputil /add-driver` rejects an unsigned INF; a **self‑signed cert — even a proper root CA in Trusted Root + Trusted Publisher — is rejected** by the driver trust provider ("...root certificate which is not trusted by the trust provider"); and the escape hatch, `bcdedit /set testsigning on`, is **ignored under Secure Boot** (on by default on ARM laptops). The only way to ship an installable custom driver is **Microsoft attestation signing** (EV cert + Partner Center).

## Options, ranked for a normal person
1. **Print from a Mac** (or any machine with the real driver). Zero setup, true 1200.
2. **`bridge/`** — a normal Windows printer that forwards to WSL/Mac/Pi. No signing, nothing resident. (This repo.)
3. **A Raspberry Pi / always‑on Linux box** sharing the printer; add it on Windows as a normal network printer.
4. **Best Windows‑only compromise (no WSL):** bind the printer to the inbox **"Brother Generic Jpeg Type2" ARM64** class driver at its highest/Photo quality — still reports 600 but often looks better than the plain IPP driver. Not true 1200.
5. **clawmon + a *signed* v3 PostScript driver** — the most elegant ("print → runs a command, fully on‑demand"), but needs the attestation‑signing effort.

## Reusable building block
The ARM64 **clawmon** port monitor (repo root) loads in the ARM spooler **unsigned** and runs a program per print job — useful for far more than this printer (print‑to‑PDF/file/automation on Windows‑on‑ARM). It just needs a signed v3 driver to be a turnkey *printer*; for everything else it works as‑is.
