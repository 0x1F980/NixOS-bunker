#!/usr/bin/env bash
# Wipe disposable (or any) zone state on the host.
# Usage: bunker-wipe <zone>
set -euo pipefail

ZONE="${1:-}"
if [[ -z "$ZONE" ]]; then
  echo "Usage: $0 <zone>"
  echo "  Example: $0 browse"
  exit 1
fi

# Prefer registry: only auto-wipe if marked disposable (override with BUNKER_WIPE_FORCE=1)
if [[ -f /etc/bunker/zones.tsv ]] && [[ "${BUNKER_WIPE_FORCE:-0}" != "1" ]]; then
  row="$(awk -F'\t' -v z="$ZONE" '$1==z {print $5}' /etc/bunker/zones.tsv || true)"
  if [[ -n "$row" && "$row" != "disposable" ]]; then
    echo "ERROR: '$ZONE' is persistent in config/zones.nix. Set BUNKER_WIPE_FORCE=1 to wipe anyway." >&2
    exit 1
  fi
fi

DATA="${BUNKER_ZONE_DATA:-/var/lib/microvms/${ZONE}}"
echo "==> wiping zone data at $DATA"
systemctl stop "microvm@${ZONE}.service" 2>/dev/null || true
pkill -f "microvm.*${ZONE}" 2>/dev/null || true
rm -rf "${DATA:?}/"*
echo "$ZONE wiped. Start again with: bunker-zone-start $ZONE"
