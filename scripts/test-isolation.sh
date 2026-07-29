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
check "clipboard zone auto-clear TTL" \
  grep -q 'schedule_zone_clear' "$ROOT/scripts/clipboard.sh" && \
  grep -q 'BUNKER_CLIP_TTL:-30' "$ROOT/scripts/clipboard.sh"
check "clipboard keeps host/global on send" \
  grep -q 'host/global clipboard KEPT' "$ROOT/scripts/clipboard.sh"
check "clipboard.conf is hackable" \
  grep -q 'clipboard.conf' "$ROOT/modules/clipboard-oneway.nix" && \
  grep -q 'TTL=30' "$ROOT/modules/clipboard-oneway.nix"

check "lib-common shared helpers" \
  test -f "$ROOT/scripts/lib-common.sh" && \
  grep -q 'bunker_zone_ip' "$ROOT/scripts/lib-common.sh" && \
  grep -q 'bunker_ssh_zone' "$ROOT/scripts/lib-common.sh"
check "operator scripts source lib-common" \
  grep -q 'lib-common.sh' "$ROOT/scripts/clipboard.sh" && \
  grep -q 'lib-common.sh' "$ROOT/scripts/usb-attach.sh" && \
  grep -q 'lib-common.sh' "$ROOT/scripts/zone-term.sh" && \
  grep -q 'lib-common.sh' "$ROOT/scripts/bunker-zone.sh"
check "no legacy zones/ stub tree" test ! -d "$ROOT/zones"
check "no tap-net / clipboard-send / nym-netvm" \
  test ! -f "$ROOT/modules/guests/tap-net.nix" && \
  test ! -f "$ROOT/scripts/clipboard-send.sh" && \
  test ! -f "$ROOT/modules/nym-netvm.nix"
check "no sdr zone alias" \
  test -z "$(grep -hnE '\bsdr\b' \
    "$ROOT/scripts/usb-attach.sh" \
    "$ROOT/scripts/usb-detach.sh" \
    "$ROOT/scripts/zone-start.sh" \
    "$ROOT/scripts/zone-term.sh" 2>/dev/null || true)"

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
check "service net/usb launchers in zones-ui" \
  grep -q 'net · netvm' "$ROOT/modules/zones-ui.nix" && \
  grep -q 'usb · usbvm' "$ROOT/modules/zones-ui.nix" && \
  grep -q 'bunker-usb-gui' "$ROOT/modules/zones-ui.nix"
check "voice · service mic anonymizer TUI" \
  test -f "$ROOT/tools/bunker-voice-tui/src/main.rs" && \
  test -f "$ROOT/modules/guests/voice.nix" && \
  grep -q 'voice · service' "$ROOT/modules/zones-ui.nix" && \
  grep -q '10.0.0.3' "$ROOT/modules/guests/voice.nix"
check "voice docs + attach scripts" \
  test -f "$ROOT/docs/voice.md" && \
  test -f "$ROOT/scripts/voice-attach.sh" && \
  grep -q '"voice"' "$ROOT/config/zones.json"
check "qube folders AppVMs Disposables Templates" \
  grep -q 'X-Qube-AppVM' "$ROOT/modules/zones-ui.nix" && \
  grep -q 'X-Qube-Template' "$ROOT/modules/zones-ui.nix" && \
  grep -q 'vault · appvm' "$ROOT/modules/zones-ui.nix"
check "no Bunker: prefix on zone titles" \
  test "$(grep -c 'Bunker:' "$ROOT/modules/zones-ui.nix" || true)" = "0"
check "julia in desktop template" \
  grep -q 'julia' "$ROOT/templates/desktop.nix"
check "bunker-zone templates command" \
  grep -q 'cmd_templates' "$ROOT/scripts/bunker-zone.sh"
check "bunker-term reaches net/usb" \
  grep -q '10.0.0.1' "$ROOT/scripts/zone-term.sh" && \
  grep -q '10.0.0.2' "$ROOT/scripts/zone-term.sh"
check "operator manpage exists" \
  test -f "$ROOT/man/bunker.1" && test -f "$ROOT/docs/MANUAL.txt"
check "host ships man bunker + MANUAL" \
  grep -q 'bunker.1' "$ROOT/modules/host-minimal.nix" && \
  grep -q 'bunker/MANUAL' "$ROOT/modules/host-minimal.nix"
check "host keeps emergency disk GUIs" \
  grep -q 'gnome-disk-utility' "$ROOT/modules/host-minimal.nix" && \
  grep -q 'gparted' "$ROOT/modules/host-minimal.nix" && \
  grep -q 'nautilus' "$ROOT/modules/host-minimal.nix" && \
  grep -q 'borgbackup' "$ROOT/modules/host-minimal.nix" && \
  grep -q 'ddrescue' "$ROOT/modules/host-minimal.nix"
check "host does not exclude disk utility" \
  test -z "$(sed -n '/excludePackages/,/^  ];$/p' "$ROOT/modules/host-minimal.nix" | grep -E 'gnome-disk-utility|nautilus|baobab|gparted' || true)"
check "help · service launcher" \
  grep -q 'help · service' "$ROOT/modules/zones-ui.nix"
check "zones · service CRUD TUI" \
  test -f "$ROOT/tools/bunker-zones-tui/src/main.rs" && \
  grep -q 'zones · service' "$ROOT/modules/zones-ui.nix" && \
  grep -q 'bunker-zones-tui' "$ROOT/modules/zones-ui.nix"
check "deniable · service + Shufflecake module" \
  test -f "$ROOT/tools/bunker-deniable-tui/src/main.rs" && \
  test -f "$ROOT/modules/shufflecake-deniable.nix" && \
  test -f "$ROOT/config/deniable-zones.json" && \
  grep -q 'deniable · service' "$ROOT/modules/zones-ui.nix" && \
  grep -q 'shufflecake-deniable' "$ROOT/hosts/bunker/configuration.nix"
check "panic · service nuclear + script" \
  test -f "$ROOT/tools/bunker-panic-tui/src/main.rs" && \
  test -f "$ROOT/scripts/bunker-panic.sh" && \
  grep -q 'panic · service' "$ROOT/modules/zones-ui.nix" && \
  grep -q 'nuclearIcon\|bunker-panic-nuclear' "$ROOT/modules/zones-ui.nix"
check "deniable docs" test -f "$ROOT/docs/deniable.md"
check "bunker-sflc unlock/lock" \
  test -f "$ROOT/scripts/bunker-sflc.sh" && \
  grep -q 'cmd_unlock' "$ROOT/scripts/bunker-sflc.sh"
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
      echo "FAIL: browse clearnet without mixnet succeeded (must fail)"
      FAIL=$((FAIL + 1))
    else
      echo "PASS: browse clearnet without mixnet failed"
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
