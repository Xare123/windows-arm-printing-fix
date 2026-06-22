# Windows‑on‑ARM — Full‑Quality Printing Fix

Get **full‑quality output** from a printer on **Windows‑on‑ARM** (Snapdragon X, Surface Pro X, etc.) when the vendor ships **no ARM64 driver** and the inbox driver gives you flat, low‑quality prints.

Born from making a **Brother MFC‑J4335DW** print as well from a Snapdragon Windows laptop as it does from a Mac. The findings and tools here apply to most **AirPrint / IPP‑Everywhere** printers, not just Brother.

---

## First — the thing nobody tells you about "1200 dpi"

Chasing a resolution *number* is usually the wrong goal. We verified with `ipptool` what this class of printer actually accepts over the network:

- It only accepts **≤ 600 dpi image input** on **every** interface — IPP (`printer-resolution-supported = 600dpi`), AirPrint/URF (`RS200-600`), and PWG‑raster (600/300). It does **not** accept PDF.
- The spec's **"1200 × 600 dpi" is the print‑head droplet placement** — an *output* the printer generates **itself** from ≤600‑dpi data.

So **there is no 1200‑dpi *input* on any OS** — your Mac sends ≤600 too. The real lever is **Print Quality = Best/High**, which engages the printer's full droplet mode. Most "Windows looks worse than the Mac" cases are simply the inbox driver **defaulting to Normal** (often over a WSD connection).

---

## Two ways to fix it

### Tier 1 — use the native printer at Best (try this first; zero install)

Add the printer to Windows as an **IPP** printer and set **Print Quality = Best** (and Color). For many people that's the whole fix — it's the same ≤600‑in → 1200×600‑dot path the Mac uses, with no extra software. If the native print still looks flat, make sure it's on a true **IPP** connection (not **WSD**) and that quality is **Best**, not Normal.

### Tier 2 — the `bridge/` in this repo — for the best color

On the Brother we tested, native Windows rasterization (GDI/Acrobat + Windows color management) came out **noticeably flatter** than the Mac, even at Best. Routing the job through **WSL + CUPS/poppler** — which rasterizes to the printer's preferred **AirPrint URF** format, exactly like macOS — restored the richer color. `bridge/` packages that as a **normal printer**:

```
App → "Full Quality (1200)" printer        (inbox Microsoft Print To PDF — already signed)
    → Local Port writes the job as a PDF
    → PrintService "document printed" event → a one‑shot Scheduled Task
    → forward.ps1 → quick Draft / Normal / Best popup → wsl armprint
    → CUPS renders (poppler → URF) and prints at full quality
```

- **One printer, pick quality per job** (popup; auto‑Best after a few seconds).
- **Nothing runs in the background** — only the spooler + Task Scheduler, as for any printer. WSL wakes for the one job and idles out.
- **Best color**, because CUPS/poppler does the rasterization, not Windows.

See **[`bridge/README.md`](bridge/README.md)**. Two non‑obvious things the setup handles for you:

- **WSL2 `networkingMode=mirrored`** — default WSL2 NAT stalls large transfers, so photo/dense pages print ~1/5 then fade to blank; mirrored networking puts WSL directly on the LAN, like the Mac.
- **`print-scaling=fit`** — even margins, instead of the printable‑area slack dumping into a big uneven bottom margin.

> **Which should you use?** Start with Tier 1 — it's free and works for most people. Reach for the bridge only if you've compared the two and want the extra color fidelity. The bridge also normalizes output across apps (every print is rendered by the same CUPS pipeline), which Tier 1 can't.

---

## `clawmon-arm64/` — the port monitor (building block + a novel artifact)

[clawmon](https://github.com/clawsoftware/clawmon) (by clawSoft, derived from Monti Lorenzo's **MFILEMON**) is a GPL‑2, RedMon‑style "redirect a printer port to a program" port monitor. **No ARM64 build existed anywhere — this is one** (cross‑compiled with **llvm‑mingw**, no Visual Studio needed; see [`BUILD.md`](BUILD.md)).

Verified on Windows 11 ARM64 (build 26220):
- ✅ `clawmon.dll` / `clawmonui.dll` / `regmon.exe` / `clawport.exe` are genuine ARM64 PE.
- ✅ The spooler **loads and registers it unsigned** (`AddMonitor` succeeds; `InitializePrintMonitor2` runs inside `spoolsv.exe`).
- ✅ A **v3** driver binds to a clawmon port.

We originally wanted clawmon to *be* the whole solution ("print → pipe to `wsl lp`, fully on‑demand, no helper"). On stock Windows that's walled by the **driver‑signing requirement**: a custom v3 PostScript driver on the port needs a Microsoft‑trusted signature, and **Secure Boot blocks test‑signing**. That wall is exactly why `bridge/` uses the inbox, already‑signed Print‑to‑PDF driver instead. The ARM64 clawmon build is kept here as a working artifact and for anyone who can supply a signed driver. Full write‑up: [`docs/windows-arm-printing.md`](docs/windows-arm-printing.md).

---

## Requirements
- Windows 11 on ARM64.
- For the **bridge**: a **WSL** Ubuntu distro (the installer can create it) + an **AirPrint / IPP‑Everywhere** printer on your LAN.
- To **build clawmon**: a WSL distro + [llvm‑mingw](https://github.com/mstorsjo/llvm-mingw). Prebuilt ARM64 binaries are in [`bin/`](bin/).

## License & credits
- **clawmon‑arm64** — **GPL‑2** (clawmon's license). Original work © Andrew Hess / clawSoft and © Monti Lorenzo (MFILEMON); ARM64 port changes are in [`CHANGES-arm64.md`](CHANGES-arm64.md). See [`LICENSE`](LICENSE) and [`CREDITS.md`](CREDITS.md).
- **bridge** — MIT (original work); see [`bridge/LICENSE`](bridge/LICENSE).

A community fix, provided as‑is. It does **not** modify or redistribute any vendor's proprietary driver — it only routes jobs to where you've legally installed one, or to the printer's own AirPrint path.
