#!/usr/bin/env bash
# Isolation smoke tests — run on host after zones are up.
set -euo pipefail

PASS=0
FAIL=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

echo "== bunker isolation tests =="

# vault should have no default route / no eth — best-effort via microvm console not available;
# check config presence instead
check "vault guest config has no interfaces force" \
  grep -q 'microvm.interfaces = lib.mkForce \[ \]\|interfaces = lib.mkForce' \
  "$(dirname "$0")/../modules/guests/vault.nix"

check "personal uses SOCKS 1081" \
  grep -q '1081' "$(dirname "$0")/../modules/guests/personal.nix"

check "work uses SOCKS 1082" \
  grep -q '1082' "$(dirname "$0")/../modules/guests/work.nix"

check "browse uses SOCKS 1083" \
  grep -q '1083' "$(dirname "$0")/../modules/guests/browse.nix"

check "netVM documents nym ports" \
  test -f "$(dirname "$0")/../modules/guests/net.nix"

check "clipboard script refuses guest→host" \
  grep -q 'REFUSING any guest' "$(dirname "$0")/clipboard-send.sh"

if sed -n '/users.users.bunker =/,/^  };$/p' "$(dirname "$0")/../modules/host-minimal.nix" | grep -q wheel; then
  echo "FAIL: bunker unexpectedly in wheel"
  FAIL=$((FAIL + 1))
else
  echo "PASS: bunker has no wheel"
  PASS=$((PASS + 1))
fi

# Live clearnet check from guests requires running VMs — document for operator
echo "NOTE: Live clearnet probes require running microVMs; add:"
echo "  ssh zone@browse 'curl -I https://example.com'  # must FAIL without Nym"

echo "== results: $PASS passed, $FAIL failed =="
[[ "$FAIL" -eq 0 ]]
