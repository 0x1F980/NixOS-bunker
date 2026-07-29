#!/usr/bin/env bash
# Start bunker microVM zones on-demand (does not embed guests into host closure).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZONES=(net usb personal work browse vault sdr)
TARGET="${1:-}"

usage() {
  echo "Usage: $0 [all|net|usb|personal|work|browse|vault|sdr]"
  echo "  Runs: nix run \"\$ROOT#zone-<name>\""
}

ensure_bridge() {
  if command -v ip >/dev/null 2>&1; then
    ip link add name br-bunker type bridge 2>/dev/null || true
    ip link set br-bunker up 2>/dev/null || true
    ip addr replace 10.0.0.254/24 dev br-bunker 2>/dev/null || true
  fi
  if systemctl list-unit-files bunker-bridge-attach.service >/dev/null 2>&1; then
    systemctl start bunker-bridge-attach.service 2>/dev/null || true
  fi
}

start_one() {
  local z="$1"
  ensure_bridge
  echo "==> starting zone '$z' via nix run .#zone-$z"
  if command -v nix >/dev/null 2>&1; then
    nix run "$ROOT#zone-$z" &
    echo "started pid $!"
    # Give tap/bridge a moment, then re-attach any leftover taps
    sleep 2
    ensure_bridge
  elif systemctl list-unit-files "microvm@$z.service" >/dev/null 2>&1; then
    systemctl start "microvm@$z.service"
  else
    echo "ERROR: nix not found and no microvm@$z.service" >&2
    exit 1
  fi
}

if [[ -z "$TARGET" || "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
  usage
  exit 1
fi

cd "$ROOT"

if [[ "$TARGET" == "all" ]]; then
  start_one net
  sleep 2
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
