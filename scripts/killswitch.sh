#!/usr/bin/env bash
# Host killswitch — drop app-guest→WAN forward; allow netVM (vm-net) egress for mixnet.
# Usage: bunker-killswitch [enable|disable|status]
set -euo pipefail

MODE="${1:-status}"
TABLE=bunker_killswitch

status() {
  nft list table inet "$TABLE" 2>/dev/null || echo "killswitch table not loaded (disabled)"
}

enable() {
  nft delete table inet "$TABLE" 2>/dev/null || true
  nft -f - <<'EOF'
table inet bunker_killswitch {
  chain forward {
    type filter hook forward priority -10; policy accept;
    # L2 / east-west on bunker bridge (app ↔ netVM SOCKS)
    iifname "br-bunker" oifname "br-bunker" accept
    # netVM may forward to WAN (Nym/Tor/DNS upstream)
    iifname "vm-net" accept
    # Drop every other guest tap → WAN
    iifname "vm-*" drop
    iifname "br-bunker" drop
  }
}
EOF
  echo "Killswitch ENABLED (app guests blocked to WAN; vm-net egress allowed)."
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
