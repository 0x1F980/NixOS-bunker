#!/usr/bin/env bash
# Host killswitch helper — block forwarding/clearnet when netVM/Nym is down.
# Usage: bunker-killswitch [enable|disable|status]
set -euo pipefail

MODE="${1:-status}"
TABLE=bunker_killswitch

status() {
  nft list table inet "$TABLE" 2>/dev/null || echo "killswitch table not loaded"
}

enable() {
  nft delete table inet "$TABLE" 2>/dev/null || true
  nft -f - <<EOF
table inet $TABLE {
  chain forward {
    type filter hook forward priority 0; policy drop;
    # Allow only if you add explicit accepts for netVM paths
  }
  chain output {
    type filter hook output priority 0; policy accept;
  }
}
EOF
  echo "Killswitch ENABLED (forward drop)."
}

disable() {
  nft delete table inet "$TABLE" 2>/dev/null || true
  echo "Killswitch DISABLED."
}

case "$MODE" in
  enable) enable ;;
  disable) disable ;;
  status) status ;;
  *) echo "Usage: $0 [enable|disable|status]"; exit 1 ;;
esac
