# Building the ARM64 binaries

Prebuilt binaries are in [`bin/`](bin/) — you only need this if you want to rebuild.

There is **no Visual Studio / Windows SDK requirement**. We cross‑compile from Linux with **llvm‑mingw**, which is the easiest toolchain to get on a Windows‑on‑ARM machine (it runs inside WSL).

## Prerequisites
1. A WSL Ubuntu (ARM64) distro — or any aarch64 Linux.
2. [llvm‑mingw](https://github.com/mstorsjo/llvm-mingw/releases) for an aarch64 Linux host, e.g.:
   ```bash
   cd /root
   curl -L -O https://github.com/mstorsjo/llvm-mingw/releases/download/<release>/llvm-mingw-<release>-ucrt-ubuntu-22.04-aarch64.tar.xz
   mkdir -p llvm-mingw && tar -C llvm-mingw --strip-components=1 -xf llvm-mingw-*.tar.xz
   ```
   (`build.sh` expects it at `/root/llvm-mingw`.)

## Build
`build.sh` copies the source to a Linux working dir, normalizes includes for the case‑sensitive FS, cross‑compiles, links statically, and drops the binaries in `build/arm64/` (copy them to `bin/`).

From WSL, with this repo at `/mnt/c/.../clawmon-arm64`:
```bash
bash build.sh
```
It builds `clawmon.dll`, `clawmonui.dll`, `regmon.exe`, and `clawport.exe`. See [`CHANGES-arm64.md`](CHANGES-arm64.md) for what each flag/patch is for.

## Install the monitor (unsigned — works)
Elevated, on the Windows side:
```powershell
# copies clawmon.dll/clawmonui.dll to System32 and runs: regmon.exe -r clawmon
.\install-clawmon.ps1
```
Then add/configure a port and add a printer with `clawport.exe` (a **v3** driver is required on the port — see `docs/windows-arm-printing.md`). Remove with `.\uninstall-clawmon.ps1`.

> Verified on Windows 11 ARM64 build 26220. The spooler accepts the unsigned monitor; the unsolved piece for a turnkey *printer* is a signed v3 driver — which is why `bridge/` exists.
