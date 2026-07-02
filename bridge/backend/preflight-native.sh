#!/bin/sh
# preflight-native.sh - diagnostic: submit a PDF to the native front-end with a
# Windows-style job ticket and trace it through nativeprint into the CUPS queue.
# NOTE: this PRINTS A PHYSICAL PAGE if the printer is online.
# Usage: preflight-native.sh <file.pdf> [port] [queue]
F="${1:?usage: preflight-native.sh <file.pdf> [port] [queue]}"
PORT="${2:-60631}"
QUEUE="${3:-FullQuality}"
cp "$F" /tmp/preflight.pdf
cat > /tmp/preflight.test <<'EOF'
{
  NAME "Print-Job with quality+sides ticket"
  OPERATION Print-Job
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri $uri
  ATTR name requesting-user-name preflight
  ATTR mimeMediaType document-format application/pdf
  GROUP job-attributes-tag
  ATTR enum print-quality 5
  ATTR keyword sides one-sided
  FILE /tmp/preflight.pdf
  STATUS successful-ok
}
EOF
echo "=== submit to front-end (port $PORT) ==="
ipptool -tv "ipp://localhost:$PORT/ipp/print" /tmp/preflight.test 2>&1 | grep -E "PASS|FAIL|job-state|job-id" | head -5
sleep 4
echo
echo "=== nativeprint handoff (want: request id ...) ==="
cat /tmp/nativeprint.log 2>/dev/null || echo "(no log)"
echo
echo "=== CUPS queue '$QUEUE' ==="
lpstat -W not-completed -o "$QUEUE" 2>/dev/null || echo "(handed to printer)"
