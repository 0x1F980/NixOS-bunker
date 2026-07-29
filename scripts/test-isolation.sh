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
check "netVM has user-net WAN iface" \
  grep -q 'type = "user"' "$ROOT/modules/guests/net.nix"

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

check "USB attach speaks QMP to usbVM only" \
  grep -q 'qmp_capabilities' "$ROOT/scripts/usb-attach.sh"
check "USB attach uses usbip broker" \
  grep -q 'usbip attach -r' "$ROOT/scripts/usb-attach.sh"
check "USB attach requires usbVM QMP" \
  grep -q 'usbVM QMP missing' "$ROOT/scripts/usb-attach.sh"
check "usbVM runs usbipd" \
  grep -q 'usbipd' "$ROOT/modules/guests/usb.nix"
check "app zones have vhci client" \
  grep -q 'vhci_hcd' "$ROOT/modules/guests/microvm-base.nix"

check "microvm QMP socket configured" \
  grep -q 'socket = lib.mkDefault "/run/microvm' "$ROOT/modules/guests/microvm-base.nix"

check "flake uses nixpkgs flakeExposed Linux ISAs" \
  grep -q 'flakeExposed' "$ROOT/flake.nix"
check "flake includes loongarch64 and s390x" \
  grep -q 'loongarch64-linux' "$ROOT/flake.nix" && grep -q 's390x-linux' "$ROOT/flake.nix"
check "arch helper maps uname to host attr" \
  test -f "$ROOT/scripts/lib-arch.sh" && grep -q 'bunker_host_flake_attr' "$ROOT/scripts/lib-arch.sh"
check "generic-linux hardware fallback exists" \
  test -f "$ROOT/hardware/generic-linux.nix"
check "infra USB/net launchers in zones-ui" \
  grep -q 'bunker-infra-net' "$ROOT/modules/zones-ui.nix" && \
  grep -q 'bunker-usb-gui' "$ROOT/modules/zones-ui.nix"
check "broker ratatui app exists" \
  test -f "$ROOT/tools/bunker-broker-tui/src/main.rs" && \
  grep -q 'bunker-broker-tui' "$ROOT/modules/zones-ui.nix"
check "bunker-term reaches net/usb" \
  grep -q '10.0.0.1' "$ROOT/scripts/zone-term.sh" && \
  grep -q '10.0.0.2' "$ROOT/scripts/zone-term.sh"
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
