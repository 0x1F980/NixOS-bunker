#!/usr/bin/env bash
# Wipe disposable zone data. Usage: bunker-wipe <zone>
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
ZONE="${1:?zone}"
if [[ -f /etc/bunker/zones.tsv && ${BUNKER_WIPE_FORCE:-0} != 1 ]]; then
  row=$(awk -F'\t' -v z="$ZONE" '$1==z {print $5}' /etc/bunker/zones.tsv || true)
  if [[ -n $row && $row != disposable ]]; then
    echo "ERROR: persistent zone — set BUNKER_WIPE_FORCE=1" >&2; exit 1
  fi
fi
if bunker_zone_is_iso "$ZONE"; then
  DATA=${BUNKER_ISO_DATA:-/var/lib/bunker/iso-zones}/$ZONE
  pkill -f "bunker:${ZONE}\\[" 2>/dev/null || true
  rm -rf "${DATA:?}/"*
  echo "$ZONE ISO wiped"; exit 0
fi
DATA=${BUNKER_ZONE_DATA:-/var/lib/microvms/$ZONE}
systemctl stop "microvm@${ZONE}.service" 2>/dev/null || true
rm -rf "${DATA:?}/"*
echo "$ZONE wiped"
