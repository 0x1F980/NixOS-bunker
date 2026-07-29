#!/usr/bin/env bash
# Isolation smoke tests — config policy + optional live probes.
# Usage: bunker-test-isolation [--live]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE=0
[[ "${1:-}" == "--live" ]] && LIVE=1

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

check "vault has no NIC (mkForce [])" \
  grep -qE 'interfaces = lib\.mkForce \[ \]' "$ROOT/modules/guests/vault.nix"

check "zones registry exists" test -f "$ROOT/config/zones.json"
check "zones.nix loads JSON" test -f "$ROOT/config/zones.nix"
check "desktop template exists" test -f "$ROOT/templates/desktop.nix"
check "browser template exists" test -f "$ROOT/templates/browser.nix"
check "mk-app-zone exists" test -f "$ROOT/modules/guests/mk-app-zone.nix"
check "bunker-zone CRUD exists" test -f "$ROOT/scripts/bunker-zone.sh"
check "zone-term exists" test -f "$ROOT/scripts/zone-term.sh"

check "example personal uses desktop template" \
  grep -q '"template": "desktop"' "$ROOT/config/zones.json"
check "example browse is disposable" \
  grep -q '"disposable": true' "$ROOT/config/zones.json"
check "example colors present" \
  grep -q '"color": "green"' "$ROOT/config/zones.json"

check "egress docs exist" test -f "$ROOT/docs/egress.md"
check "i2p alternative in netVM" \
  grep -q 'socksProxy.port = 4447' "$ROOT/modules/guests/net.nix"

check "killswitch allows vm-net egress" \
  grep -q 'iifname "vm-net" accept' "$ROOT/scripts/killswitch.sh"

check "killswitch drops other vm-*" \
  grep -q 'iifname "vm-\*" drop' "$ROOT/scripts/killswitch.sh"

check "clipboard refuses guest→host" \
  grep -q 'BLOCKED' "$ROOT/scripts/clipboard.sh"
check "clipboard has zone copy" \
  grep -q 'cmd_copy' "$ROOT/scripts/clipboard.sh"
check "clipboard has auto-clear" \
  grep -q 'BUNKER_CLIP_TTL' "$ROOT/scripts/clipboard.sh"

check "USB attach speaks QMP" \
  grep -q 'qmp_capabilities' "$ROOT/scripts/usb-attach.sh"

check "USB attach fails without socket" \
  grep -q 'ERROR: no QMP socket' "$ROOT/scripts/usb-attach.sh"

check "microvm QMP socket configured" \
  grep -q 'socket = lib.mkDefault "/run/microvm' "$ROOT/modules/guests/microvm-base.nix"

check "hardware-config is stub (must replace)" \
  grep -q 'STUB' "$ROOT/hosts/bunker/hardware-configuration.nix"

if sed -n '/users.users.bunker =/,/^  };$/p' "$ROOT/modules/host-minimal.nix" | grep -q wheel; then
  echo "FAIL: bunker unexpectedly in wheel"
  FAIL=$((FAIL + 1))
else
  echo "PASS: bunker has no wheel"
  PASS=$((PASS + 1))
fi

if [[ "$LIVE" -eq 1 ]]; then
  echo "-- live probes --"
  if ping -c1 -W2 10.0.0.13 >/dev/null 2>&1; then
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no zone@10.0.0.13 \
      'curl -m 5 -I https://example.com' >/dev/null 2>&1; then
      echo "FAIL: browse clearnet without proxy succeeded (must fail)"
      FAIL=$((FAIL + 1))
    else
      echo "PASS: browse clearnet without proxy failed"
      PASS=$((PASS + 1))
    fi
  else
    echo "SKIP live: browse VM 10.0.0.13 not reachable"
  fi
else
  echo "NOTE: run with --live after bunker-zone-start net && bunker-zone-start browse"
fi

echo "== results: $PASS passed, $FAIL failed =="
[[ "$FAIL" -eq 0 ]]
