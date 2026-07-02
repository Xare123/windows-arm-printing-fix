#!/bin/sh
# nativeprint - print command run by ippeveprinter for each job on the native
# front-end. ippeveprinter passes the spooled document as $1 (stdin fallback
# kept for safety); the Windows print dialog's choices arrive as IPP_*
# environment variables. NATIVEPRINT_QUEUE is exported by ippeve-supervisor
# (from /etc/ippeve-native.conf).
f="$1"
if [ -z "$f" ] || [ ! -s "$f" ]; then
  f=$(mktemp /tmp/nativeprint-XXXXXX.pdf); cat > "$f"; CLEAN=1
fi
q="High"
case "${IPP_PRINT_QUALITY:-}" in
  3|draft)  q="Draft"  ;;
  4|normal) q="Normal" ;;
  5|high)   q="High"   ;;
esac
s="${IPP_SIDES:-one-sided}"
set -- -o cupsPrintQuality="$q" -o sides="$s" -o print-scaling=fit -o ColorModel=RGB -o MediaType=Stationery
[ -n "${IPP_MEDIA:-}" ] && set -- "$@" -o media="$IPP_MEDIA"
[ "${IPP_PRINT_COLOR_MODE:-}" = "monochrome" ] && set -- "$@" -o print-color-mode=monochrome
# make sure the CUPS scheduler is up (cold-boot race), then hand off; append to
# the log so earlier jobs' outcomes stay visible for diagnosis
systemctl is-active --quiet cups 2>/dev/null || systemctl start cups 2>/dev/null || service cups start 2>/dev/null
echo "$(date -Is) job: quality=$q sides=$s media=${IPP_MEDIA:-default}" >> /tmp/nativeprint.log
lp -d "${NATIVEPRINT_QUEUE:-FullQuality}" -n "${IPP_COPIES:-1}" "$@" "$f" >> /tmp/nativeprint.log 2>&1
rc=$?
[ -n "$CLEAN" ] && rm -f "$f"
exit $rc
