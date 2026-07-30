#!/usr/bin/env bash
# Isolation smoke — minimal zone model.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

echo "== bunker isolation =="

check "zones.json" test -f "$ROOT/config/zones.json"
check "invisible field" grep -q '"invisible"' "$ROOT/config/zones.json"
check "panic field" grep -q '"panic"' "$ROOT/config/zones.json"
check "bunker-tui" test -f "$ROOT/tools/bunker-tui/src/main.rs"
check "zones-ui" grep -q 'bunker-tui' "$ROOT/modules/zones-ui.nix"
check "no deniable-zones.json" test ! -f "$ROOT/config/deniable-zones.json"
check "no old TUIs" test ! -d "$ROOT/tools/bunker-zones-tui"
check "flake x86 only" grep -q 'x86_64-linux' "$ROOT/flake.nix"
check "no multi-arch theater" bash -c "! grep -q 'loongarch\|powerpc\|mipsel' \"$ROOT/flake.nix\""
check "no zone-cursor" test ! -f "$ROOT/modules/guests/zone-cursor.nix"
check "no firejail on host" bash -c "! grep -q 'firejail' \"$ROOT/modules/hardening.nix\""
check "hardening.nix" test -f "$ROOT/modules/hardening.nix"
check "openssh force" grep -q 'mkForce true' "$ROOT/modules/host-minimal.nix"
check "sflc→zones.json" grep -q 'zones.json' "$ROOT/scripts/lib-shufflecake.sh"
check "zone-start invisible" grep -Eq 'invisible_blocked|require_invisible' "$ROOT/scripts/zone-start.sh"

echo "== $PASS passed, $FAIL failed =="
[[ "$FAIL" -eq 0 ]]
