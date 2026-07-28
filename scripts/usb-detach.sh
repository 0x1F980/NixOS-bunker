#!/usr/bin/env bash
# Detach USB device from a VM assignment record.
# Usage: bunker-usb-detach <vm> <busid>
set -euo pipefail

VM="${1:-}"
BUSID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"

if [[ -z "$VM" || -z "$BUSID" ]]; then
  echo "Usage: $0 <vm> <usb-busid>"
  exit 1
fi

if [[ -f "$STATE_DIR/$BUSID" ]]; then
  cur="$(cat "$STATE_DIR/$BUSID")"
  if [[ "$cur" != "$VM" ]]; then
    echo "ERROR: $BUSID is assigned to '$cur', not '$VM'" >&2
    exit 1
  fi
  rm -f "$STATE_DIR/$BUSID"
  echo "Detached record $BUSID from $VM"
else
  echo "No assignment record for $BUSID"
fi
