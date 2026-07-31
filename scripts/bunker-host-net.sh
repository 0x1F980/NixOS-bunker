#!/usr/bin/env bash
# Host clearnet lock (Qubes-like). Usage: bunker-host-net [lock|allow|status]
set -euo pipefail
MODE="${1:-status}"

lock() {
  nft delete table inet bunker_host 2>/dev/null || true
  nft -f - <<'EOF'
table inet bunker_host {
  chain output {
    type filter hook output priority filter; policy drop;
    oifname "lo" accept
    ip daddr 127.0.0.0/8 accept
    ip daddr 10.0.0.0/24 accept
    ip6 daddr ::1 accept
    ct state established,related accept
    udp dport 67 accept
    udp sport 68 accept
  }
}
EOF
  systemctl start bunker-host-net-lock.service 2>/dev/null || true
  echo "HOST CLEARNET LOCKED (lo + bunker LAN only)."
}

allow() {
  nft delete table inet bunker_host 2>/dev/null || true
  systemctl stop bunker-host-net-lock.service 2>/dev/null || true
  echo "HOST CLEARNET ALLOWED — rebuild/update, then: bunker-host-net lock"
}

status() {
  if nft list table inet bunker_host >/dev/null 2>&1; then
    echo "locked"
    nft list table inet bunker_host
  else
    echo "allowed (no bunker_host table)"
  fi
}

case "$MODE" in
  lock|enable) lock ;;
  allow|disable|unlock) allow ;;
  status) status ;;
  *) echo "Usage: $0 lock|allow|status"; exit 1 ;;
esac
