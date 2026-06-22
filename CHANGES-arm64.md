# ARM64 port — changes vs. upstream clawmon

What it took to cross‑compile clawmon for **Windows ARM64** with **llvm‑mingw** (clang, `aarch64-w64-mingw32`) from WSL, and to make a printer actually bind to its port. Upstream is the MSVC/x86/x64 clawmon; these are the deltas.

### Source changes (in `src/`)
| File | Change | Why |
|---|---|---|
| `monitor/evp_stub.h` (new) | No‑op replacements for the few OpenSSL `EVP_*` symbols. | clawmon used AES only to obfuscate a "run‑as user" password; the bundled `libeay32` is x86/x64‑only. Stubs return failure → existing code stores an empty password. Removes the only third‑party dependency. |
| `monitor/portlist.cpp` | `#include <openssl\evp.h>` → `#include "evp_stub.h"`; **`PORT_INFO_2.fPortType = 0` → `PORT_TYPE_WRITE`**. | Drop OpenSSL; and the modern ARM spooler won't let a printer bind to a port that doesn't advertise `PORT_TYPE_WRITE`. |
| `monitor/stdafx.cpp` | Removed the MSVC `FILE _iob[]` / `__iob_func` shim. | Existed only to satisfy the old x86 `libeay32`; wrong/unneeded under mingw‑ucrt. |
| `common/sec_api.h` | Added `#include <_mingw.h>` before the `MINGW_HAS_SECURE_API` test. | Modern mingw already provides the secure CRT (`*_s`) functions; without this the shim redefines them and calls a 3‑arg `vswprintf`. |
| `regmon/regmon.cpp` | Register the monitor under **`szMonitorName` ("clawmon")**, not a descriptive name; accept the name as `argv[2]`. | `EnumPorts` reports each port's `pMonitorName` as `szMonitorName`; the spooler looks the monitor up by that exact name when binding a printer, so the registered name **must** match. |
| `clawport/clawport.cpp` (new) | Small CLI: `add`/`set`/`del` ports via `XcvData`, and `addprinter` via raw `AddPrinterW`. | `Add-Printer` (CIM) can't bind printers to third‑party monitor ports; raw `AddPrinterW` can. Also a clean way to script port config. |

### Build‑system (in `build.sh`)
- Cross‑compile each target with `aarch64-w64-mingw32-clang++`; **statically link** the runtime (`-static`) so the DLLs depend only on Windows system libraries (otherwise `LoadLibrary` fails with error 126 — missing `libc++`/`libunwind`/`libwinpthread`).
- Normalize includes for the case‑sensitive Linux FS: lowercase `<...>` system headers (`LMCons.h`→`lmcons.h`) and convert `..\common\` backslashes to `/` on `#include` lines.
- Forced‑include a tiny compat header for `min`/`max` macros + `<stdlib.h>`/`<time.h>` (MSVC pulled these implicitly).
- Defines: `-DUNICODE -D_UNICODE -DMINGW_HAS_SECURE_API=1`; compile `monitorUI` with `-DCLAWMONUI` (the string `extern`s in `defs.h` are gated by it).
- Resources via `windres` with `-DUNICODE -DCLAWMONLANG=0x409`.

### Result
`bin/clawmon.dll`, `bin/clawmonui.dll`, `bin/regmon.exe`, `bin/clawport.exe` — all `IMAGE_FILE_MACHINE_ARM64` (0xAA64), importing only Windows system DLLs. Verified: the spooler loads the monitor **unsigned**, and a printer binds to a clawmon port with a **v3** driver.
