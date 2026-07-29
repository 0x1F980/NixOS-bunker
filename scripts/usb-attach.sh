#!/usr/bin/env bash
# Attach one USB device to one microVM via QMP (device_add usb-host).
# Usage: bunker-usb-attach <vm> <vendorId:productId>   e.g. bunker-usb-attach radio 0bda:2838
set -euo pipefail

VM="${1:-}"
DEVID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"
MON_DIR="${BUNKER_QEMU_MON:-/var/lib/microvms}"

usage() {
  echo "Usage: $0 <vm> <vendorId:productId>"
  echo "  Example: $0 radio 0bda:2838"
  echo "  List: lsusb"
}

qmp() {
  local sock="$1"
  local cmd="$2"
  # QMP requires capabilities handshake then the command
  if command -v socat >/dev/null 2>&1; then
    {
      sleep 0.05
      printf '%s\n' '{"execute":"qmp_capabilities"}'
      sleep 0.05
      printf '%s\n' "$cmd"
    } | socat - UNIX-CONNECT:"$sock"
  else
    echo "ERROR: socat required for QMP" >&2
    return 1
  fi
}

if [[ -z "$VM" || -z "$DEVID" ]]; then
  usage
  exit 1
fi

if [[ ! "$DEVID" =~ ^[0-9a-fA-F]+:[0-9a-fA-F]+$ ]]; then
  echo "ERROR: device must be vendor:product hex (lsusb)" >&2
  exit 1
fi

VENDOR="${DEVID%:*}"
PRODUCT="${DEVID#*:}"
mkdir -p "$STATE_DIR"

if [[ -f "$STATE_DIR/$DEVID" ]]; then
  cur="$(cat "$STATE_DIR/$DEVID")"
  echo "ERROR: $DEVID already attached to '$cur'. Detach first." >&2
  exit 1
fi

MON=""
for cand in \
  "/run/microvm/${VM}.sock" \
  "$MON_DIR/$VM/sock" \
  "$MON_DIR/$VM/qemu.sock" \
  "$MON_DIR/$VM/monitor.sock" \
  "/run/microvm/$VM/monitor.sock"
do
  if [[ -S "$cand" ]]; then
    MON="$cand"
    break
  fi
done

if [[ -z "$MON" ]]; then
  echo "ERROR: no QMP socket for '$VM' (expected /run/microvm/${VM}.sock)." >&2
  echo "Start the zone first: bunker-zone-start $VM" >&2
  exit 1
fi

VID="0x${VENDOR}"
PID="0x${PRODUCT}"
USBID="usb_${VENDOR}_${PRODUCT}"
CMD=$(printf '{"execute":"device_add","arguments":{"driver":"usb-host","vendorid":%s,"productid":%s,"id":"%s","bus":"xhci.0"}}' \
  "$((VID))" "$((PID))" "$USBID")

if ! qmp "$MON" "$CMD"; then
  echo "ERROR: QMP device_add failed via $MON" >&2
  exit 1
fi

echo "$VM" >"$STATE_DIR/$DEVID"
echo "Attached $DEVID -> $VM via $MON"
