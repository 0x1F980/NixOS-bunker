#!/usr/bin/env bash
# Attach USB device to a microVM via QMP (device_add usb-host).
#
# Hardware truth: one physical USB device can be LIVE in only one VM at a time.
# Policy: same device MAY be listed for many zones (defaults); attach MOVES it
# if another zone currently holds it (unless BUNKER_USB_EXCLUSIVE=1 refuses move).
#
# Usage: bunker-usb-attach <vm> <vendorId:productId>
set -euo pipefail

VM="${1:-}"
DEVID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"
MON_DIR="${BUNKER_QEMU_MON:-/var/lib/microvms}"
EXCLUSIVE="${BUNKER_USB_EXCLUSIVE:-0}"

usage() {
  echo "Usage: $0 <vm> <vendorId:productId>"
  echo "  Example: $0 radio 0bda:2838"
  echo "  List: lsusb"
  echo "  Many zones can declare the same device in zones.json usb[];"
  echo "  live attach is still one VM at a time (hardware) — we MOVE on re-attach."
}

qmp() {
  local sock="$1"
  local cmd="$2"
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

find_mon() {
  local vm="$1"
  local cand
  for cand in \
    "/run/microvm/${vm}.sock" \
    "$MON_DIR/$vm/sock" \
    "$MON_DIR/$vm/qemu.sock" \
    "$MON_DIR/$vm/monitor.sock"
  do
    if [[ -S "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
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
USBID="usb_${VENDOR}_${PRODUCT}"
mkdir -p "$STATE_DIR"

# If held by another VM, move (detach then attach) unless exclusive mode
if [[ -f "$STATE_DIR/$DEVID" ]]; then
  cur="$(cat "$STATE_DIR/$DEVID")"
  if [[ "$cur" == "$VM" ]]; then
    echo "Already on $VM"
    exit 0
  fi
  if [[ "$EXCLUSIVE" == "1" ]]; then
    echo "ERROR: $DEVID held by '$cur' (BUNKER_USB_EXCLUSIVE=1). Detach first." >&2
    exit 1
  fi
  echo "NOTE: moving $DEVID from $cur → $VM (one live holder; hardware limit)"
  "$(dirname "$0")/usb-detach.sh" "$cur" "$DEVID" || true
fi

MON="$(find_mon "$VM" || true)"
if [[ -z "$MON" ]]; then
  echo "ERROR: no QMP socket for '$VM' (expected /run/microvm/${VM}.sock)." >&2
  echo "Start the zone first: bunker-zone-start $VM" >&2
  exit 1
fi

VID="0x${VENDOR}"
PID="0x${PRODUCT}"
CMD=$(printf '{"execute":"device_add","arguments":{"driver":"usb-host","vendorid":%s,"productid":%s,"id":"%s","bus":"xhci.0"}}' \
  "$((VID))" "$((PID))" "$USBID")

if ! qmp "$MON" "$CMD"; then
  echo "ERROR: QMP device_add failed via $MON" >&2
  exit 1
fi

echo "$VM" >"$STATE_DIR/$DEVID"
# Record which zones are allowed (from zones.json) — informational
echo "Attached $DEVID → $VM (live). Other zones may list it in usb[] but only one holds it live."
