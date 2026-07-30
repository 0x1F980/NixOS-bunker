#!/usr/bin/env bash
# Detach USB. Usage: bunker-usb-detach <zone> <vid:pid>
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
ZONE=${1:?}; DEVID=${2:?}
STATE=${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}
V=${DEVID%:*}; P=${DEVID#*:}; USBID=usb_${V}_${P}
if bunker_zone_is_iso "$ZONE"; then
  MON=$(bunker_qmp_sock "$ZONE" || true)
  [[ -n ${MON:-} ]] && bunker_qmp "$MON" "{\"execute\":\"device_del\",\"arguments\":{\"id\":\"$USBID\"}}" >/dev/null || true
  rm -f "$STATE/$DEVID"; echo "OK ISO detach"; exit 0
fi
ZIP=$(bunker_zone_ip "$ZONE"); [[ -n $ZIP ]] || { echo "no IP"; exit 1; }
bunker_ssh_zone "$ZIP" "sudo usbip detach -p 0" 2>/dev/null || bunker_ssh_zone "$ZIP" "sudo usbip detach -p 1" 2>/dev/null || true
rm -f "$STATE/$DEVID"; echo "OK detach $DEVID from $ZONE"
