#!/bin/sh
# AirPrint / IPP-Everywhere backend for the Full Quality Print Bridge.
#
# No vendor driver, no qemu, no resolution cap: CUPS + cups-filters drive the printer's
# native AirPrint path (renders the PDF with poppler -> URF and lets the printer halftone
# at full quality). Works with ANY AirPrint / IPP-Everywhere printer, not just Brother.
#
# Usage:  setup-airprint-backend.sh [PRINTER]
#   (no arg)            -> auto-discover the first AirPrint printer on the LAN (ippfind)
#   192.168.1.50        -> ipp://192.168.1.50/ipp/print
#   ipp://host/ipp/print -> used as-is
QUEUE="FullQuality"

echo "== install CUPS + cups-filters (native ARM, no emulation) =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y cups cups-client cups-filters cups-ipp-utils >/dev/null 2>&1 || true

echo "== resolve printer URI =="
ARG="$1"
URI=""
case "$ARG" in
  ipp://*|ipps://*) URI="$ARG" ;;
  "") echo "  no printer given - trying to auto-discover via ippfind (mDNS; may not work in WSL)..."
      ALL="$(ippfind --timeout 6 2>/dev/null | grep -E '^ipps?://')"
      if [ -n "$ALL" ]; then echo "  found:"; echo "$ALL" | sed 's/^/    /'; fi
      URI="$(printf '%s\n' "$ALL" | head -1)"
      if [ "$(printf '%s\n' "$ALL" | grep -c .)" -gt 1 ]; then
        echo "  (multiple printers found - using the FIRST; re-run with an IP to choose a specific one)"
      fi ;;
  *)  URI="ipp://$ARG/ipp/print" ;;
esac
if [ -z "$URI" ]; then
  echo "  !! no printer found. Re-run with your printer's IP, e.g.:  setup-airprint-backend.sh 192.168.1.50" >&2
  exit 1
fi
echo "  using: $URI"

echo "== enable + start cups (autostarts on every WSL boot via systemd) =="
systemctl enable cups >/dev/null 2>&1 || true
systemctl start cups  >/dev/null 2>&1 || service cups start >/dev/null 2>&1 || true
cupsctl DirtyCleanInterval=0 >/dev/null 2>&1 || true   # persist config immediately (WSL can be killed)
sleep 1

echo "== create driverless (AirPrint) queue '$QUEUE' -> $URI =="
lpadmin -p "$QUEUE" -E -v "$URI" -m everywhere 2>&1
cupsenable "$QUEUE" 2>/dev/null || true
cupsaccept "$QUEUE" 2>/dev/null || true
sleep 1

echo "== install /usr/local/bin/armprint helper =="
cat > /usr/local/bin/armprint <<EOS
#!/bin/sh
# armprint <quality> <sides> <file>  -- print one file via the AirPrint queue.
#   quality = Draft | Normal | High             (cupsPrintQuality; "Best" maps to High)
#   sides   = one-sided | two-sided-long-edge    (Double-sided = two-sided-long-edge)
q="\${1:-High}"; s="\${2:-two-sided-long-edge}"; f="\$3"
[ -f "\$f" ] || { echo "armprint: file not found: \$f" >&2; exit 1; }
# make sure the scheduler is up (cold WSL boot race) before printing
systemctl is-active --quiet cups 2>/dev/null || systemctl start cups 2>/dev/null || service cups start 2>/dev/null
i=0; while [ \$i -lt 20 ]; do lpstat -r >/dev/null 2>&1 && break; sleep 0.5; i=\$((i + 1)); done
exec lp -d $QUEUE -o cupsPrintQuality="\$q" -o ColorModel=RGB -o MediaType=Stationery -o print-scaling=fit -o sides="\$s" "\$f"
EOS
chmod +x /usr/local/bin/armprint

echo "== verify =="
lpstat -v "$QUEUE" 2>&1 || true
echo "AIRPRINT-BACKEND-DONE"
