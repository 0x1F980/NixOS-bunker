#!/usr/bin/env bash
# Attach one USB device to one microVM (Qubes-like one-at-a-time).
# Usage: bunker-usb-attach <vm> <busid>   e.g. bunker-usb-attach sdr 1-2
set -euo pipefail

VM="${1:-}"
BUSID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"

usage() {
  echo "Usage: $0 <vm> <usb-busid>"
  echo "  Example: $0 sdr 1-4"
  echo "  List devices: lsusb -t"
}

if [[ -z "$VM" || -z "$BUSID" ]]; then
  usage
  exit 1
fi

mkdir -p "$STATE_DIR"

# Enforce one-at-a-time: refuse if busid already assigned
if [[ -f "$STATE_DIR/$BUSID" ]]; then
  cur="$(cat "$STATE_DIR/$BUSID")"
  echo "ERROR: device $BUSID already attached to VM '$cur'. Detach first." >&2
  exit 1
fi

echo "$VM" >"$STATE_DIR/$BUSID"
echo "Recorded assign $BUSID -> $VM"
echo "NOTE: Complete hotplug with your microvm/QEMU device_add for vendor:product."
echo "      Example (manual): virsh/qemu-monitor device_add usb-host,hostbus=...,hostaddr=..."
echo "Policy: only one VM may hold a given device."
