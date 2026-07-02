#!/bin/sh
# setup-native-frontend.sh - install the NATIVE-printer IPP front-end.
#
# What this gives you: a normal Windows printer (added with the inbox
# Microsoft IPP Class Driver, no vendor driver, no signing) whose jobs are
# rendered by CUPS/poppler - the same pipeline macOS/AirPrint uses - so color
# comes out vivid instead of the flat output Windows' own rasterizer produces:
#
#   Windows app -> native print dialog -> IPP Class Driver
#     -> ippeveprinter (this front-end, port 60631, advertises PDF ONLY)
#     -> nativeprint helper (maps the dialog's quality/sides/media/copies)
#     -> lp -> CUPS driverless queue (poppler renders -> URF) -> printer
#
# Why not point Windows at cupsd directly? Windows sends Microsoft's
# proprietary "windows-ext" IPP operation; cupsd answers
# client-error-bad-request and Windows aborts without submitting the job.
# ippeveprinter handles unknown operations gracefully.
#
# Why advertise application/pdf only? It forces Windows to send an intact PDF
# (its driver converts XPS->PDF), so Windows never rasterizes and cannot
# flatten the color. Verified byte-identical sRGB end to end.
#
# Works with ANY printer that has a CUPS driverless queue (see
# setup-airprint-backend.sh) - Brother, Canon, Epson, HP, etc.
#
# Usage: setup-native-frontend.sh [queue] [port] [name] [duplex 0|1]
#   queue  - CUPS queue to print through (default FullQuality)
#   port   - TCP port for the front-end   (default 60631)
#   name   - printer name shown in IPP    (default "Full Color Printer")
#   duplex - 1 if the printer can duplex  (default 1)
QUEUE="${1:-FullQuality}"
PORT="${2:-60631}"
NAME="${3:-Full Color Printer}"
DUPLEX="${4:-1}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== ensure ippeveprinter is installed =="
command -v ippeveprinter >/dev/null 2>&1 || {
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y cups-ipp-utils >/dev/null 2>&1
}
command -v ippeveprinter >/dev/null 2>&1 || { echo "!! ippeveprinter missing (install cups-ipp-utils)"; exit 1; }

echo "== write /etc/ippeve-native.conf (queue=$QUEUE port=$PORT duplex=$DUPLEX) =="
printf 'QUEUE="%s"\nPORT=%s\nNAME="%s"\nDUPLEX=%s\n' "$QUEUE" "$PORT" "$NAME" "$DUPLEX" > /etc/ippeve-native.conf

echo "== install nativeprint + supervisor =="
tr -d '\r' < "$DIR/nativeprint.sh"      > /usr/local/bin/nativeprint      && chmod +x /usr/local/bin/nativeprint
tr -d '\r' < "$DIR/ippeve-supervisor.sh" > /usr/local/bin/ippeve-supervisor && chmod +x /usr/local/bin/ippeve-supervisor
mkdir -p /var/spool/ippeve

echo "== autostart at distro boot (/etc/wsl.conf [boot] command) =="
touch /etc/wsl.conf
if grep -q "ippeve-supervisor" /etc/wsl.conf; then
  : # already wired
elif grep -qE '^[[:space:]]*command[[:space:]]*=' /etc/wsl.conf; then
  # WSL honors only ONE [boot] command; never clobber or shadow the user's.
  echo "!! /etc/wsl.conf already has a [boot] command - NOT touching it."
  echo "!! To autostart the front-end, add this to your existing boot command:"
  echo "     nohup setsid /usr/local/bin/ippeve-supervisor >/dev/null 2>&1 &"
elif grep -q "^\[boot\]" /etc/wsl.conf; then
  # insert the command line right after the existing [boot] header
  sed -i 's|^\[boot\]|[boot]\ncommand = /bin/sh -c "nohup setsid /usr/local/bin/ippeve-supervisor >/dev/null 2>\&1 \&"|' /etc/wsl.conf
else
  printf '\n[boot]\ncommand = /bin/sh -c "nohup setsid /usr/local/bin/ippeve-supervisor >/dev/null 2>&1 &"\n' >> /etc/wsl.conf
fi

echo "== (re)start the front-end now =="
[ -f /run/ippeve-supervisor.pid ] && kill "$(cat /run/ippeve-supervisor.pid)" 2>/dev/null
pkill -x ippeve-supervis 2>/dev/null   # comm name is truncated to 15 chars
pkill -x ippeveprinter 2>/dev/null
rm -f /run/ippeve-supervisor.pid
sleep 1
# detach fds fully: an inherited stdout pipe would keep the CALLER's pipeline
# open forever (e.g. `setup... | tail` never sees EOF)
if command -v setsid >/dev/null 2>&1; then
  setsid --fork /usr/local/bin/ippeve-supervisor </dev/null >/dev/null 2>&1
else
  nohup /usr/local/bin/ippeve-supervisor </dev/null >/dev/null 2>&1 &
fi
sleep 4

echo "== verify =="
if ss -tln 2>/dev/null | grep -q ":$PORT "; then
  echo "front-end LISTENING on port $PORT"
else
  echo "!! front-end not listening; last log lines:"
  tail -5 /var/log/ippeve-native.log 2>/dev/null
  exit 1
fi
echo "NATIVE-FRONTEND-DONE"
