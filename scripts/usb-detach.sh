#!/usr/bin/env bash
# Detach USB device from a VM (QMP device_del) + clear policy record.
# Usage: bunker-usb-detach <vm> <vendorId:productId>
set -euo pipefail

VM="${1:-}"
DEVID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"
MON_DIR="${BUNKER_QEMU_MON:-/var/lib/microvms}"

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

if [[ -z "$VM" || -z "$DEVID" ]]; then
  echo "Usage: $0 <vm> <vendorId:productId>"
  exit 1
fi

VENDOR="${DEVID%:*}"
PRODUCT="${DEVID#*:}"
USBID="usb_${VENDOR}_${PRODUCT}"

if [[ -f "$STATE_DIR/$DEVID" ]]; then
  cur="$(cat "$STATE_DIR/$DEVID")"
  if [[ "$cur" != "$VM" ]]; then
    echo "ERROR: $DEVID is assigned to '$cur', not '$VM'" >&2
    exit 1
  fi
fi

MON=""
for cand in \
  "/run/microvm/${VM}.sock" \
  "$MON_DIR/$VM/sock" \
  "$MON_DIR/$VM/qemu.sock" \
  "$MON_DIR/$VM/monitor.sock"
do
  if [[ -S "$cand" ]]; then
    MON="$cand"
    break
  fi
done

if [[ -z "$MON" ]]; then
  echo "ERROR: no QMP socket for '$VM'" >&2
  exit 1
fi

CMD=$(printf '{"execute":"device_del","arguments":{"id":"%s"}}' "$USBID")
qmp "$MON" "$CMD" || {
  echo "ERROR: QMP device_del failed" >&2
  exit 1
}

rm -f "$STATE_DIR/$DEVID"
echo "Detached $DEVID from $VM"
