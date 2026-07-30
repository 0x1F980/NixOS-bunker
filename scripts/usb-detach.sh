#!/usr/bin/env bash
# Detach USB from an app zone (usbip) or ISO zone (QMP device_del).
# Usage: bunker-usb-detach <zone> <vendorId:productId>
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

ZONE="${1:-}"
DEVID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"
MON_DIR="${BUNKER_QEMU_MON:-/var/lib/microvms}"

if [[ -z "$ZONE" || -z "$DEVID" ]]; then
  echo "Usage: $0 <zone> <vendorId:productId>"
  exit 1
fi

VENDOR="${DEVID%:*}"
PRODUCT="${DEVID#*:}"
USBID="usb_${VENDOR}_${PRODUCT}"

find_mon() {
  local vm="$1" cand
  for cand in \
    "/run/microvm/${vm}.sock" \
    "$MON_DIR/$vm/sock" \
    "$MON_DIR/$vm/qemu.sock"
  do
    [[ -S "$cand" ]] && { echo "$cand"; return 0; }
  done
  return 1
}

qmp() {
  local sock="$1" cmd="$2"
  {
    sleep 0.05
    printf '%s\n' '{"execute":"qmp_capabilities"}'
    sleep 0.05
    printf '%s\n' "$cmd"
  } | socat - UNIX-CONNECT:"$sock"
}

if [[ -f "$STATE_DIR/$DEVID" ]]; then
  cur="$(cut -d' ' -f1 "$STATE_DIR/$DEVID")"
  if [[ "$cur" != "$ZONE" ]]; then
    echo "WARN: state says holder is '$cur', detaching $ZONE anyway"
  fi
fi

if bunker_zone_is_iso "$ZONE"; then
  MON="$(find_mon "$ZONE" || true)"
  if [[ -n "$MON" ]]; then
    echo "==> QMP: device_del $USBID from ISO zone $ZONE"
    qmp "$MON" "{\"execute\":\"device_del\",\"arguments\":{\"id\":\"$USBID\"}}" >/dev/null || true
  else
    echo "WARN: no QMP for $ZONE (already stopped?)" >&2
  fi
  rm -f "$STATE_DIR/$DEVID"
  echo "OK: $DEVID released from ISO zone $ZONE"
  exit 0
fi

ZIP="$(bunker_zone_ip "$ZONE")"
[[ -n "$ZIP" ]] || {
  echo "ERROR: unknown zone $ZONE" >&2
  exit 1
}

echo "==> $ZONE: usbip detach"
bunker_ssh_zone "$ZIP" "sudo usbip detach -p 0" 2>/dev/null || \
  bunker_ssh_zone "$ZIP" "sudo usbip detach -p 1" 2>/dev/null || \
  bunker_ssh_zone "$ZIP" "sudo usbip detach -p 2" 2>/dev/null || true

rm -f "$STATE_DIR/$DEVID"
echo "OK: $DEVID released from $ZONE (still on usbVM broker for other zones)"
