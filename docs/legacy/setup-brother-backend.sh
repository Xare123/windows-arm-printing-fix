#!/bin/sh
# Sets up the Brother MFC-J4335DW real Linux driver inside WSL so it can render at 1200.
# Runs as root inside the distro (systemd must already be enabled + booted).
# Usage: setup-brother-backend.sh [printer-ip]
set -e
export DEBIAN_FRONTEND=noninteractive
PRINTER_IP="${1:-192.168.1.95}"
MODEL=mfcj4335dw
QUEUE=MFCJ4335DW
DEB_URL="https://download.brother.com/pub/com/linux/linux/packages/mfcj4335dwpdrv-3.5.0-1.i386.deb"

echo "== DNS sanity =="
getent hosts archive.ubuntu.com >/dev/null 2>&1 || { rm -f /etc/resolv.conf; printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >/etc/resolv.conf; }

echo "== add amd64 multiarch (Brother ships an x86_64 driver; we run it via qemu) =="
F=/etc/apt/sources.list.d/ubuntu.sources
[ -f "$F" ] && ! grep -q '^Architectures:' "$F" && sed -i 's|^Types: deb|Types: deb\nArchitectures: arm64|g' "$F" || true
cat >/etc/apt/sources.list.d/amd64.sources <<EOF
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: noble noble-updates
Components: main universe
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
dpkg --add-architecture amd64

echo "== install CUPS + qemu + amd64 glibc =="
apt-get update
apt-get install -y --no-install-recommends \
  cups cups-client cups-filters ghostscript qemu-user-static binfmt-support \
  file wget ca-certificates curl libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64

echo "== start CUPS + make config writes immediate =="
systemctl enable cups >/dev/null 2>&1 || true
systemctl start cups  >/dev/null 2>&1 || true
cupsctl DirtyCleanInterval=0 || true

echo "== download + unpack Brother driver =="
cd /root
curl -L --retry 3 -o brdrv.deb "$DEB_URL"
dpkg-deb -x brdrv.deb /            # lands at /opt/brother/Printers/mfcj4335dw/
BASE=/opt/brother/Printers/$MODEL
[ -d "$BASE" ] || { echo "ERROR: driver tree missing at $BASE"; exit 1; }

echo "== qemu wrappers for the x86_64 Brother binaries (no native ARM build exists) =="
for BIN in brmfcj4335dwfilter brprintconf_mfcj4335dw; do
  cat > "$BASE/lpd/$BIN" <<WRAP
#!/bin/sh
export QEMU_LD_PREFIX=/
exec /usr/bin/qemu-x86_64-static "$BASE/lpd/x86_64/$BIN" "\$@"
WRAP
  chmod 755 "$BASE/lpd/$BIN"
done
chmod 755 "$BASE/lpd/filter_$MODEL" "$BASE/cupswrapper/brother_lpdwrapper_$MODEL" 2>/dev/null || true
chmod 755 "$BASE"/lpd/x86_64/* "$BASE"/inf/* 2>/dev/null || true

echo "== install PPD + CUPS filter =="
mkdir -p /usr/share/cups/model/Brother
cp -f "$BASE/cupswrapper/brother_${MODEL}_printer_en.ppd" /usr/share/cups/model/Brother/
ln -sf "$BASE/cupswrapper/brother_lpdwrapper_$MODEL" "/usr/lib/cups/filter/brother_lpdwrapper_$MODEL"

echo "== create the CUPS queue -> printer at $PRINTER_IP =="
lpadmin -x $QUEUE 2>/dev/null || true
lpadmin -p $QUEUE -E -v "socket://$PRINTER_IP:9100" -P "$BASE/cupswrapper/brother_${MODEL}_printer_en.ppd"
cupsenable $QUEUE 2>/dev/null || true
cupsaccept $QUEUE 2>/dev/null || true

echo "== verify =="
lpstat -v $QUEUE
echo "BACKEND-DONE"
