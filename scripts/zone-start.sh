#!/usr/bin/env bash
# Start bunker microVM zones (on-demand).
set -euo pipefail

ZONES=(net usb personal work browse vault sdr)
TARGET="${1:-}"

usage() {
  echo "Usage: $0 [all|net|usb|personal|work|browse|vault|sdr]"
}

start_one() {
  local z="$1"
  echo "==> starting microvm '$z'"
  if command -v microvm >/dev/null 2>&1; then
    microvm -c "$z" || systemctl start "microvm@$z.service" || true
  else
    systemctl start "microvm@$z.service"
  fi
}

if [[ -z "$TARGET" || "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
  usage
  exit 1
fi

if [[ "$TARGET" == "all" ]]; then
  # Prefer net first, then others (skip vault unless asked — still included in all)
  start_one net
  for z in usb personal work browse sdr vault; do
    start_one "$z"
  done
  exit 0
fi

for z in "${ZONES[@]}"; do
  if [[ "$TARGET" == "$z" ]]; then
    start_one "$z"
    exit 0
  fi
done

echo "Unknown zone: $TARGET" >&2
usage
exit 1
