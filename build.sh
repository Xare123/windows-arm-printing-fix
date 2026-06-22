#!/bin/sh
# Cross-compile clawmon for Windows ARM64 with llvm-mingw, from WSL.
# Source of truth: /mnt/c/Claude/clawmon-arm64/src
TC=/root/llvm-mingw/bin
export PATH="$TC:$PATH"
CXX=aarch64-w64-mingw32-clang++
CC=aarch64-w64-mingw32-clang
RC=aarch64-w64-mingw32-windres
OD=/root/llvm-mingw/bin/aarch64-w64-mingw32-objdump
RO=/root/llvm-mingw/bin/llvm-readobj

echo "== winsplp.h MONITOR2/MONITORINIT present? =="
grep -cE 'MONITOR2|MONITORINIT|PMONITORINIT' /root/llvm-mingw/generic-w64-mingw32/include/winsplp.h

rm -rf /root/clawsrc && cp -a /mnt/c/Claude/clawmon-arm64/src /root/clawsrc
cd /root/clawsrc || exit 1
# normalize includes for the case-sensitive cross toolchain:
find . -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.c' -o -name '*.rc' \) -print0 \
  | xargs -0 sed -i '/#[ \t]*include/ s#\\#/#g'
find . -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.c' -o -name '*.rc' \) -print0 \
  | xargs -0 sed -i -E '/#[ \t]*include[ \t]*</ s/<([^>]+)>/<\L\1\E>/'

cat > /root/clawcompat.h <<'EOF'
#include <stdlib.h>
#include <time.h>
#ifndef min
#define min(a,b) (((a)<(b))?(a):(b))
#endif
#ifndef max
#define max(a,b) (((a)>(b))?(a):(b))
#endif
EOF

OUT=/root/clawout; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$OUT/err.log"
DEF="-DUNICODE -D_UNICODE -DWIN32 -D_WINDOWS -D_WIN32_WINNT=0x0A00 -DNDEBUG -DMINGW_HAS_SECURE_API=1"
INC="-Icommon -Imonitor -ImonitorUI -Iregmon"
WARN="-Wno-format -Wno-unknown-pragmas -Wno-nonportable-include-path -Wno-deprecated-declarations -Wno-writable-strings"
CXXFLAGS="-O2 $DEF $INC $WARN -include /root/clawcompat.h"
# link runtime statically so the DLL/EXE depend only on Windows system libs
LDFLAGS="-static -static-libgcc -static-libstdc++"
fail=0
cxx(){ echo "  CXX $1"; $CXX $CXXFLAGS -c "$1" -o "$2" 2>>"$OUT/err.log" || { echo "   *** FAILED $1"; fail=1; }; }

echo "== compile common =="
cxx common/defs.cpp      "$OUT/c_defs.o"
cxx common/monutils.cpp  "$OUT/c_monutils.o"
cxx common/autoclean.cpp "$OUT/c_autoclean.o"
echo "  CC  common/sec_api.c"; $CC -O2 $DEF $INC -c common/sec_api.c -o "$OUT/c_sec.o" 2>>"$OUT/err.log" || { echo "   *** FAILED sec_api.c"; fail=1; }

echo "== compile monitor =="
for f in monitor port portlist pattern patsegment log stdafx; do cxx monitor/$f.cpp "$OUT/m_$f.o"; done
echo "== compile monitorUI (needs -DCLAWMONUI to expose the UI string externs in defs.h) =="
for f in monitorUI stdafx; do echo "  CXX monitorUI/$f.cpp"; $CXX $CXXFLAGS -DCLAWMONUI -c monitorUI/$f.cpp -o "$OUT/u_$f.o" 2>>"$OUT/err.log" || { echo "   *** FAILED monitorUI/$f.cpp"; fail=1; }; done
echo "== compile regmon =="
for f in regmon stdafx; do cxx regmon/$f.cpp "$OUT/r_$f.o"; done

echo "== resources (non-fatal) =="
$RC $INC -DUNICODE -D_UNICODE -DCLAWMONLANG=0x409 -i monitor/resource.rc   -o "$OUT/m_res.o" 2>>"$OUT/err.log" && echo "  rc monitor OK" || echo "  rc monitor FAILED (link without)"
$RC $INC -DUNICODE -D_UNICODE -DCLAWMONLANG=0x409 -i monitorUI/resource.rc -o "$OUT/u_res.o" 2>>"$OUT/err.log" && echo "  rc ui OK"      || echo "  rc ui FAILED (link without)"

[ $fail -ne 0 ] && { echo; echo "===== COMPILE ERRORS ====="; sed -n '1,120p' "$OUT/err.log"; echo "----- (continuing to link what succeeded) -----"; }

have(){ for o in "$@"; do [ -f "$o" ] || return 1; done; return 0; }
MRES=""; [ -f "$OUT/m_res.o" ] && MRES="$OUT/m_res.o"
URES=""; [ -f "$OUT/u_res.o" ] && URES="$OUT/u_res.o"
COMMON="$OUT/c_defs.o $OUT/c_monutils.o $OUT/c_autoclean.o $OUT/c_sec.o"
MON="$OUT/m_monitor.o $OUT/m_port.o $OUT/m_portlist.o $OUT/m_pattern.o $OUT/m_patsegment.o $OUT/m_log.o $OUT/m_stdafx.o"
UI="$OUT/u_monitorUI.o $OUT/u_stdafx.o"
REG="$OUT/r_regmon.o $OUT/r_stdafx.o"

echo "== link clawmon.dll =="
if have $MON $COMMON; then
  $CXX $LDFLAGS -shared -o "$OUT/clawmon.dll" $MON $COMMON $MRES monitor/clawmon.def \
    -luserenv -lwinspool -ladvapi32 -luser32 -lpsapi 2>>"$OUT/err.log" && echo "  clawmon.dll OK" || { echo "  *** LINK clawmon FAILED"; tail -25 "$OUT/err.log"; }
else echo "  skip clawmon.dll (compile failures)"; fi

echo "== link clawmonui.dll =="
if have $UI $COMMON; then
  $CXX $LDFLAGS -shared -o "$OUT/clawmonui.dll" $UI $COMMON $URES monitorUI/clawmonui.def \
    -lwinspool -luser32 -lshell32 -lcomctl32 -ladvapi32 2>>"$OUT/err.log" && echo "  clawmonui.dll OK" || { echo "  *** LINK ui FAILED"; tail -25 "$OUT/err.log"; }
else echo "  skip clawmonui.dll (compile failures)"; fi

echo "== link regmon.exe =="
if have $REG $COMMON; then
  $CXX $LDFLAGS -municode -o "$OUT/regmon.exe" $REG $COMMON -lwinspool -ladvapi32 2>>"$OUT/err.log" && echo "  regmon.exe OK" || { echo "  *** LINK regmon FAILED"; tail -25 "$OUT/err.log"; }
else echo "  skip regmon.exe (compile failures)"; fi

echo "== compile + link clawport.exe (Xcv AddPort/SetConfig CLI) =="
if $CXX $CXXFLAGS -c clawport/clawport.cpp -o "$OUT/cp.o" 2>>"$OUT/err.log"; then
  $CXX $LDFLAGS -municode -o "$OUT/clawport.exe" "$OUT/cp.o" -lwinspool -ladvapi32 -luser32 2>>"$OUT/err.log" && echo "  clawport.exe OK" || { echo "  *** LINK clawport FAILED"; tail -20 "$OUT/err.log"; }
else echo "  *** COMPILE clawport FAILED"; tail -20 "$OUT/err.log"; fi

echo "== results =="
ls -l "$OUT"/*.dll "$OUT"/*.exe 2>/dev/null
for b in clawmon.dll clawmonui.dll regmon.exe; do
  [ -f "$OUT/$b" ] || continue
  echo "-- $b --"
  $RO --file-headers "$OUT/$b" 2>/dev/null | grep -i 'Machine'
  echo "  exports:"; $OD -p "$OUT/$b" 2>/dev/null | grep -iE 'InitializePrintMonitor' | sed 's/^/    /'
  echo "  imported DLLs:"; $OD -p "$OUT/$b" 2>/dev/null | grep -i 'DLL Name' | sed 's/^/    /'
done
mkdir -p /mnt/c/Claude/clawmon-arm64/build/arm64
cp -f "$OUT"/*.dll "$OUT"/*.exe /mnt/c/Claude/clawmon-arm64/build/arm64/ 2>/dev/null
echo "== artifacts on Windows side =="; ls -l /mnt/c/Claude/clawmon-arm64/build/arm64/ 2>/dev/null
echo "BUILD-SCRIPT-DONE"
