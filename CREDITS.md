# Credits & attribution

This project stands on prior GPL‑2 work. The ARM64 port and the `bridge/` tool are the only new parts.

- **clawmon** — © Andrew Hess / **clawSoft**. The RedMon‑style redirection port monitor this repo ports to ARM64. Part of [clawPDF](https://github.com/clawsoftware/clawPDF) / [clawmon](https://github.com/clawsoftware/clawmon). Licensed **GPL‑2**.
- **MFILEMON** — © **Monti Lorenzo** (2007–2015). The original "print to file with automatic filename assignment" monitor that clawmon derives from. Licensed **GPL‑2**.
- **ARM64 port** (this repo, 2026) — cross‑compilation, source fixes, the `clawport` CLI, and documentation of the Windows‑on‑ARM driver/signing walls. Changes are listed in [`CHANGES-arm64.md`](CHANGES-arm64.md). Remains **GPL‑2**.
- **llvm‑mingw** — © Martin Storsjö. The LLVM/MinGW toolchain used to cross‑compile the ARM64 binaries. (Build tool only; not redistributed here.)
- **`bridge/`** — original work, licensed **MIT** (it contains no clawmon code; it only orchestrates inbox Windows components).

No vendor's proprietary printer driver is included, modified, or redistributed by this project.
