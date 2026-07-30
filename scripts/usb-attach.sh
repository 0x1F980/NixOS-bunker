#!/usr/bin/env bash
# Attach USB: usbip via usbVM, or QMP for ISO. Usage: bunker-usb-attach <zone> <vid:pid>
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
ZONE=${1:?}; DEVID=${2:?}
STATE=${BUNKER_USB_STATE:-/var/lib/bunker/usb-assign}; mkdir -p "$STATE"
[[ $DEVID =~ ^[0-9a-fA-F]+:[0-9a-fA-F]+$ ]] || { echo "vid:pid"; exit 1; }
case $ZONE in usb|net) echo "not a broker"; exit 1;; esac
V=${DEVID%:*}; P=${DEVID#*:}; USBID=usb_${V}_${P}

if bunker_zone_is_iso "$ZONE"; then
  MON=$(bunker_qmp_sock "$ZONE") || { echo "start zone first"; exit 1; }
  bunker_qmp "$MON" "$(printf '{"execute":"device_add","arguments":{"driver":"usb-host","vendorid":%s,"productid":%s,"id":"%s","bus":"xhci.0"}}' "$((0x$V))" "$((0x$P))" "$USBID")" >/dev/null
  echo "$ZONE direct" >"$STATE/$DEVID"; echo "OK $DEVID → ISO $ZONE"; exit 0
fi

ZIP=$(bunker_zone_ip "$ZONE"); [[ -n $ZIP ]] || { echo "no IP"; exit 1; }
MON=$(bunker_qmp_sock usb) || { echo "start usbVM"; exit 1; }
if ! bunker_ssh_zone 10.0.0.2 "sudo lsusb -d $DEVID" >/dev/null 2>&1; then
  bunker_qmp "$MON" "$(printf '{"execute":"device_add","arguments":{"driver":"usb-host","vendorid":%s,"productid":%s,"id":"%s","bus":"xhci.0"}}' "$((0x$V))" "$((0x$P))" "$USBID")" >/dev/null
  sleep 1
fi
BUSID=$(bunker_ssh_zone 10.0.0.2 "sudo bunker-usb-broker bind $DEVID" | tail -n1 | tr -d '\r')
[[ -n $BUSID && $BUSID != ERROR* ]] || { echo "bind fail"; exit 1; }
if [[ -f $STATE/$DEVID ]]; then
  cur=$(cut -d' ' -f1 "$STATE/$DEVID")
  if [[ $cur != "$ZONE" && -n $cur ]]; then
    if bunker_zone_is_iso "$cur"; then
      CM=$(bunker_qmp_sock "$cur" || true)
      [[ -n ${CM:-} ]] && bunker_qmp "$CM" "{\"execute\":\"device_del\",\"arguments\":{\"id\":\"$USBID\"}}" >/dev/null || true
    else
      CIP=$(bunker_zone_ip "$cur")
      [[ -n $CIP ]] && bunker_ssh_zone "$CIP" "sudo usbip detach -p 0" 2>/dev/null || true
    fi
  fi
fi
bunker_ssh_zone "$ZIP" "sudo usbip attach -r 10.0.0.2 -b $BUSID"
echo "$ZONE $BUSID" >"$STATE/$DEVID"
echo "OK $DEVID → $ZONE"
