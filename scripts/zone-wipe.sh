#!/usr/bin/env bash
# Wipe disposable zone data. Usage: bunker-wipe <zone>
# Applies to app zones and brokers (net/usb) when kind=disposable.
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
ZONE="${1:?zone}"
RID=$(bunker_zone_runtime_id "$ZONE")
RID=${RID:-$ZONE}

is_disp=false
if bunker_zone_is_disposable "$ZONE"; then
  is_disp=true
elif [[ -f /etc/bunker/zones.tsv ]]; then
  row=$(awk -F'\t' -v z="$ZONE" '$1==z {print $5}' /etc/bunker/zones.tsv || true)
  [[ $row == disposable ]] && is_disp=true
fi
if [[ $is_disp != true && ${BUNKER_WIPE_FORCE:-0} != 1 ]]; then
  echo "ERROR: persistent zone — set BUNKER_WIPE_FORCE=1" >&2
  exit 1
fi

if bunker_zone_is_iso "$ZONE"; then
  DATA=${BUNKER_ISO_DATA:-/var/lib/bunker/iso-zones}/$ZONE
  pkill -f "bunker:${ZONE}\\[" 2>/dev/null || true
  rm -rf "${DATA:?}/"*
  echo "$ZONE ISO wiped"
  exit 0
fi

DATA=${BUNKER_ZONE_DATA:-/var/lib/microvms/$RID}
systemctl stop "microvm@${RID}.service" 2>/dev/null || true
herd stop "bunker-vm-${RID}" 2>/dev/null || true
pkill -f "bunker:${RID}" 2>/dev/null || true
rm -rf "${DATA:?}/"*
echo "$ZONE wiped (vm=$RID)"
