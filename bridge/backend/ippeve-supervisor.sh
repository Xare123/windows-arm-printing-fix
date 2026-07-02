#!/bin/sh
# ippeve-supervisor - keeps the native IPP front-end alive (restart-on-crash).
# Launched from /etc/wsl.conf [boot] command at distro start. Deliberately NOT
# a systemd unit: a plain loop is portable and has no exec-context surprises.
#
# Config: /etc/ippeve-native.conf   (QUEUE, PORT, NAME, DUPLEX)
QUEUE="FullQuality"; PORT=60631; NAME="Full Color Printer"; DUPLEX=1
[ -f /etc/ippeve-native.conf ] && . /etc/ippeve-native.conf
LOG=/var/log/ippeve-native.log
PIDFILE=/run/ippeve-supervisor.pid
[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null && exit 0  # already running
echo $$ > "$PIDFILE"
export NATIVEPRINT_QUEUE="$QUEUE"
D2=""; [ "$DUPLEX" = "1" ] && D2="-2"
mkdir -p /var/spool/ippeve
while :; do
  echo "$(date -Is) starting ippeveprinter (queue=$QUEUE port=$PORT name=$NAME)" >> "$LOG"
  # LANDMINE (ippeveprinter.c, CUPS 2.4.x, ~line 655): -P/-a are mutually
  # exclusive with the "legacy" options, and -f/-2/-M/-m/-s ALL set the legacy
  # flag; combining them exits with a SILENT usage dump (no error message).
  # So never add -P here. -f application/pdf is the color guarantee: it forces
  # Windows to send an intact PDF, so all rasterization happens in CUPS.
  # -r off skips DNS-SD registration (Windows connects directly by port, and
  # a flaky/absent avahi otherwise crashes or wedges startup).
  /usr/sbin/ippeveprinter -r off $D2 -f application/pdf \
    -p "$PORT" -c /usr/local/bin/nativeprint -d /var/spool/ippeve \
    "$NAME" >> "$LOG" 2>&1
  echo "$(date -Is) exited rc=$? - restarting in 5s" >> "$LOG"
  sleep 5
done
