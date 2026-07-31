#!/usr/bin/env bash
# Start microVM or ISO zone. Usage: bunker-zone-start <zone|all>
# Hidden friendly names resolve to anonymous slots (d1..) after SFLC unlock.
set -euo pipefail
SDIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
source "$SDIR/lib-common.sh"
SYS=(net usb)
TARGET="${1:-}"
ZJ="$(bunker_zones_json)"
# Flake root when developing; empty on installed host (use systemd microvm@)
FLAKE_ROOT="${BUNKER_FLAKE:-}"
if [[ -z $FLAKE_ROOT ]]; then
  for p in "$(cd "$SDIR/.." && pwd)" "$HOME/NixOS-bunker" /home/user/nixos-bunker; do
    [[ -f $p/flake.nix ]] && FLAKE_ROOT=$p && break
  done
fi

zones() {
  # Prefer merged registry (public ∪ unlocked hidden)
  if [[ -f /run/bunker/zones-merged.json ]]; then
    python3 -c "import json;print('\\n'.join(json.load(open('/run/bunker/zones-merged.json'))))"
    return
  fi
  if [[ -f /etc/bunker/zones.tsv ]]; then
    cut -f1 /etc/bunker/zones.tsv
  elif [[ -f $ZJ ]]; then
    python3 -c "import json;print('\\n'.join(json.load(open('$ZJ'))))"
  fi
}

require_unlocked() {
  local z=$1
  if ! python3 -c "import json,sys;sys.exit(0 if sys.argv[1] in json.load(open(sys.argv[2])) else 1)" "$z" "$ZJ" 2>/dev/null; then
    echo "ERROR: unknown zone '$z' — unlock SFLC (u) if hidden, or check zones.json" >&2
    exit 1
  fi
  # Public zones (no slot / not invisible) always OK
  python3 - "$ZJ" "$z" <<'PY' || return 0
import json,sys
c=(json.load(open(sys.argv[1])).get(sys.argv[2]) or {})
sys.exit(0 if (c.get("invisible") or c.get("slot")) else 1)
PY
  if [[ -f /run/bunker/visible-zones.json ]] && python3 -c "import json,sys;sys.exit(0 if sys.argv[1] in json.load(open('/run/bunker/visible-zones.json')) else 1)" "$z"; then
    return 0
  fi
  echo "ERROR: hidden zone '$z' locked — unlock in TUI (u) or bunker-sflc unlock <layer>" >&2
  exit 1
}

bridge() {
  ip link add name br-bunker type bridge 2>/dev/null || true
  ip link set br-bunker up 2>/dev/null || true
  ip addr replace 10.0.0.254/24 dev br-bunker 2>/dev/null || true
  systemctl start bunker-bridge-attach.service 2>/dev/null || true
}

start_one() {
  local z=$1
  local rid
  # Brokers (net/usb) are always startable; app zones need unlock if hidden
  if ! bunker_zone_is_broker "$z"; then
    require_unlocked "$z"
  fi
  rid=$(bunker_zone_runtime_id "$z")
  [[ -n $rid ]] || rid=$z
  bridge
  # Disposable: wipe disk before start (incl. disposable netVM / usbVM)
  if bunker_zone_is_disposable "$z"; then
    echo "disposable $z — wiping before start"
    "$SDIR/zone-wipe.sh" "$z" || true
  fi
  if bunker_zone_is_iso "$z"; then
    "$SDIR/iso-run.sh" "$z" &
  elif systemctl cat "microvm@${rid}.service" &>/dev/null; then
    systemctl start "microvm@${rid}.service"
  elif [[ -n ${FLAKE_ROOT:-} ]] && command -v nix >/dev/null; then
    nix run "$FLAKE_ROOT#zone-$rid" &
  else
    echo "ERROR: cannot start $z (runtime $rid: no microvm unit / flake)" >&2
    exit 1
  fi
  echo "started $z (vm=$rid)"
  sleep 2
  bridge
  local usbs
  usbs=$(python3 -c "import json;print(','.join(json.load(open('$ZJ')).get('$z',{}).get('usb') or []))" 2>/dev/null || true)
  IFS=',' read -ra D <<<"${usbs:-}"
  for d in "${D[@]}"; do
    [[ -n $d ]] && "$SDIR/usb-attach.sh" "$z" "$d" || true
  done
}

[[ -n $TARGET && $TARGET != -h ]] || {
  echo "Usage: $0 <zone|all>"
  zones | sed 's/^/  /'
  exit 1
}

mapfile -t APP < <(zones | grep -vxE 'net|usb' || true)
if [[ $TARGET == all ]]; then
  start_one net
  sleep 2
  start_one usb
  for z in "${APP[@]}"; do
    [[ -n $z ]] && start_one "$z"
  done
  exit 0
fi
for z in "${SYS[@]}" "${APP[@]}"; do
  [[ $TARGET == "$z" ]] && {
    start_one "$z"
    exit 0
  }
done
# Also allow starting by slot id directly if merged knows it
if python3 -c "import json,sys;sys.exit(0 if sys.argv[1] in json.load(open('$(bunker_zones_json)')) else 1)" "$TARGET" 2>/dev/null; then
  start_one "$TARGET"
  exit 0
fi
echo "Unknown: $TARGET" >&2
exit 1
