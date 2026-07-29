#!/usr/bin/env bash
# Detach USB from an app zone (usbip). Device stays on usbVM ready for another zone.
# Usage: bunker-usb-detach <zone> <vendorId:productId>
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

ZONE="${1:-}"
DEVID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"

if [[ -z "$ZONE" || -z "$DEVID" ]]; then
  echo "Usage: $0 <zone> <vendorId:productId>"
  exit 1
fi

ZIP="$(bunker_zone_ip "$ZONE")"
[[ -n "$ZIP" ]] || {
  echo "ERROR: unknown zone $ZONE" >&2
  exit 1
}

if [[ -f "$STATE_DIR/$DEVID" ]]; then
  cur="$(cut -d' ' -f1 "$STATE_DIR/$DEVID")"
  if [[ "$cur" != "$ZONE" ]]; then
    echo "WARN: state says holder is '$cur', detaching $ZONE anyway"
  fi
fi

echo "==> $ZONE: usbip detach"
bunker_ssh_zone "$ZIP" "sudo usbip detach -p 0" 2>/dev/null || \
  bunker_ssh_zone "$ZIP" "sudo usbip detach -p 1" 2>/dev/null || \
  bunker_ssh_zone "$ZIP" "sudo usbip detach -p 2" 2>/dev/null || true

rm -f "$STATE_DIR/$DEVID"
echo "OK: $DEVID released from $ZONE (still on usbVM broker for other zones)"
