#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
check() { local n=$1; shift; if "$@"; then echo "PASS: $n"; PASS=$((PASS+1)); else echo "FAIL: $n"; FAIL=$((FAIL+1)); fi; }
echo "== bunker =="
check "zones.json" test -f "$ROOT/config/zones.json"
check "bunker-tui full CRUD" grep -qE 'Mode::Add|cycle_color|rename_zone|delete_zone' "$ROOT/tools/bunker-tui/src/main.rs"
check "per-zone hide unlock" grep -qE 'unlock-zone|hideHash|next_free_layer|Mode::UnlockPass' "$ROOT/tools/bunker-tui/src/main.rs"
check "sflc unlock-zone" grep -q 'unlock-zone)' "$ROOT/scripts/bunker-sflc.sh"
check "bunker-tui nym/i2p/tor" grep -q 'nym.*i2p.*tor' "$ROOT/tools/bunker-tui/src/main.rs"
check "iso-run" test -f "$ROOT/scripts/iso-run.sh"
check "net has nym" grep -q 'nym-client' "$ROOT/modules/guests/net.nix"
check "net has i2pd" grep -q 'i2pd' "$ROOT/modules/guests/net.nix"
check "net has tor" grep -q 'services.tor' "$ROOT/modules/guests/net.nix"
check "no host mat2" bash -c "! grep -q mat2 \"$ROOT/modules/host-minimal.nix\""
check "zone terminal color" grep -q 'BUNKER_ZONE_COLOR\|color.ansi' "$ROOT/modules/guests/mk-app-zone.nix"
check "invisible" grep -q '"invisible"' "$ROOT/config/zones.json"
check "panic" grep -q '"panic"' "$ROOT/config/zones.json"
echo "== $PASS passed, $FAIL failed =="
[[ $FAIL -eq 0 ]]
