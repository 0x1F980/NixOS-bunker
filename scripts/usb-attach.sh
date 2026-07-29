#!/usr/bin/env bash
# USB 1→many via usbVM broker (usbip), same pattern as netVM for network.
#
# Flow:
#   1) Host QMP attaches physical device ONLY to usbVM (10.0.0.2)
#   2) usbVM binds/exports with usbip
#   3) Target zone imports via usbip (many zones can request; one holds live)
#
# Usage: bunker-usb-attach <zone> <vendorId:productId>
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

ZONE="${1:-}"
DEVID="${2:-}"
STATE_DIR="${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}"
MON_DIR="${BUNKER_QEMU_MON:-/var/lib/microvms}"
USB_IP="10.0.0.2"

usage() {
  echo "Usage: $0 <zone> <vendorId:productId>"
  echo "  Broker: usbVM $USB_IP  →  many app zones (usbip)"
  echo "  Example: $0 radio 0bda:2838"
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

if [[ -z "$ZONE" || -z "$DEVID" ]]; then
  usage
  exit 1
fi
if [[ ! "$DEVID" =~ ^[0-9a-fA-F]+:[0-9a-fA-F]+$ ]]; then
  echo "ERROR: need vid:pid hex" >&2
  exit 1
fi
if [[ "$ZONE" == "usb" || "$ZONE" == "net" || "$ZONE" == "vault" ]]; then
  echo "ERROR: attach to an app zone (personal/work/browse/radio/…), not $ZONE" >&2
  exit 1
fi

ZIP="$(bunker_zone_ip "$ZONE")"
[[ -n "$ZIP" ]] || {
  echo "ERROR: unknown zone IP for $ZONE" >&2
  exit 1
}

mkdir -p "$STATE_DIR"
VENDOR="${DEVID%:*}"
PRODUCT="${DEVID#*:}"
USBID="usb_${VENDOR}_${PRODUCT}"

# --- 1) Ensure device is on usbVM (host QMP → usb only) ---
MON="$(find_mon usb || true)"
[[ -n "$MON" ]] || {
  echo "ERROR: usbVM QMP missing. Start broker: bunker-zone-start usb" >&2
  exit 1
}

# If already listed on usb via lsusb, skip QMP; else device_add
if ! bunker_ssh_zone "$USB_IP" "sudo lsusb -d $DEVID" >/dev/null 2>&1; then
  echo "==> QMP: attach $DEVID to usbVM"
  CMD=$(printf '{"execute":"device_add","arguments":{"driver":"usb-host","vendorid":%s,"productid":%s,"id":"%s","bus":"xhci.0"}}' \
    "$((0x${VENDOR}))" "$((0x${PRODUCT}))" "$USBID")
  qmp "$MON" "$CMD" >/dev/null || {
    echo "ERROR: QMP device_add to usbVM failed" >&2
    exit 1
  }
  sleep 1
fi

# --- 2) Bind/export on usbVM ---
echo "==> usbVM: bind/export $DEVID"
BUSID="$(bunker_ssh_zone "$USB_IP" "sudo bunker-usb-broker bind $DEVID" | tail -n1 | tr -d '\r')"
if [[ -z "$BUSID" || "$BUSID" == ERROR* ]]; then
  echo "ERROR: could not bind $DEVID on usbVM (got: ${BUSID:-empty})" >&2
  exit 1
fi
echo "    busid=$BUSID"

# --- 3) If another zone holds it, detach there first ---
if [[ -f "$STATE_DIR/$DEVID" ]]; then
  cur="$(cut -d' ' -f1 "$STATE_DIR/$DEVID")"
  if [[ "$cur" != "$ZONE" && -n "$cur" ]]; then
    echo "==> move: detach from $cur"
    CIP="$(bunker_zone_ip "$cur")"
    if [[ -n "$CIP" ]]; then
      bunker_ssh_zone "$CIP" "sudo usbip detach -p 0" 2>/dev/null || \
        bunker_ssh_zone "$CIP" "sudo usbip detach -p 1" 2>/dev/null || true
    fi
  fi
fi

# --- 4) Import into target zone ---
echo "==> $ZONE ($ZIP): usbip attach from $USB_IP"
bunker_ssh_zone "$ZIP" "sudo usbip attach -r $USB_IP -b $BUSID"

echo "$ZONE $BUSID" >"$STATE_DIR/$DEVID"
echo "OK: $DEVID brokered usbVM → $ZONE (1 usbVM → many zones; this device live on $ZONE)"
