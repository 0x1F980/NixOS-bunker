#!/usr/bin/env bash
# Detach USB from an app zone (usbip). Device stays on usbVM ready for another zone.
# Usage: bunker-usb-detach <zone> <vendorId:productId>
set -euo pipefail

ZONE="${1:-}"
DEVID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"
ZONE_PASS="${BUNKER_ZONE_PASS:-zone}"
USB_IP="10.0.0.2"

lookup_zone_ip() {
  local name="$1"
  case "$name" in
    sdr) name=radio ;;
  esac
  if [[ -f /etc/bunker/zones.json ]]; then
    python3 -c "import json;z=json.load(open('/etc/bunker/zones.json'));print(z.get('$name',{}).get('ip',''))" 2>/dev/null && return
  fi
  if [[ -f "$(dirname "$0")/../config/zones.json" ]]; then
    python3 -c "import json;z=json.load(open('$(dirname "$0")/../config/zones.json'));print(z.get('$name',{}).get('ip',''))" 2>/dev/null && return
  fi
  echo ""
}

ssh_z() {
  local ip="$1"
  shift
  local opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
  if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$ZONE_PASS" ssh "${opts[@]}" -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no "zone@${ip}" "$@"
  else
    ssh "${opts[@]}" "zone@${ip}" "$@"
  fi
}

if [[ -z "$ZONE" || -z "$DEVID" ]]; then
  echo "Usage: $0 <zone> <vendorId:productId>"
  exit 1
fi

ZIP="$(lookup_zone_ip "$ZONE")"
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
ssh_z "$ZIP" "sudo usbip detach -p 0" 2>/dev/null || \
  ssh_z "$ZIP" "sudo usbip detach -p 1" 2>/dev/null || \
  ssh_z "$ZIP" "sudo usbip detach -p 2" 2>/dev/null || true

# Keep device exported on usbVM for next zone (unbind optional)
# ssh_z "$USB_IP" "sudo bunker-usb-broker unbind $DEVID" || true

rm -f "$STATE_DIR/$DEVID"
echo "OK: $DEVID released from $ZONE (still on usbVM broker for other zones)"
