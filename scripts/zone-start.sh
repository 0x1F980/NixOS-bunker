#!/usr/bin/env bash
# Start microVM or ISO zone. Usage: bunker-zone-start <zone|all>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-common.sh
source "$ROOT/scripts/lib-common.sh"
SYS=(net usb)
TARGET="${1:-}"

zones() {
  if [[ -f /etc/bunker/zones.tsv ]]; then cut -f1 /etc/bunker/zones.tsv
  elif [[ -f $ROOT/config/zones.json ]]; then
    python3 -c "import json;print('\\n'.join(json.load(open('$ROOT/config/zones.json'))))"
  fi
  [[ -f /run/bunker/visible-zones.json ]] && python3 -c "import json;print('\\n'.join(json.load(open('/run/bunker/visible-zones.json'))))" 2>/dev/null || true
}

require_unlocked() {
  local z=$1 zj=${ROOT}/config/zones.json
  [[ -f /etc/bunker/zones.json ]] && zj=/etc/bunker/zones.json
  python3 - "$zj" "$z" <<'PY' || return 0
import json,sys
c=(json.load(open(sys.argv[1])).get(sys.argv[2]) or {})
sys.exit(0 if c.get("invisible") else 1)
PY
  if [[ -f /run/bunker/visible-zones.json ]] && python3 -c "import json,sys;sys.exit(0 if sys.argv[1] in json.load(open('/run/bunker/visible-zones.json')) else 1)" "$z"; then
    return 0
  fi
  echo "ERROR: hidden zone '$z' locked — bunker-sflc unlock <layer>" >&2; exit 1
}

bridge() {
  ip link add name br-bunker type bridge 2>/dev/null || true
  ip link set br-bunker up 2>/dev/null || true
  ip addr replace 10.0.0.254/24 dev br-bunker 2>/dev/null || true
  systemctl start bunker-bridge-attach.service 2>/dev/null || true
}

start_one() {
  local z=$1; require_unlocked "$z"; bridge
  if bunker_zone_is_iso "$z"; then
    "$ROOT/scripts/iso-run.sh" "$z" &
  elif command -v nix >/dev/null; then
    nix run "$ROOT#zone-$z" &
  elif systemctl list-unit-files "microvm@$z.service" >/dev/null 2>&1; then
    systemctl start "microvm@$z.service"
  else
    echo "ERROR: cannot start $z" >&2; exit 1
  fi
  echo "started $z"; sleep 2; bridge
  local usbs
  usbs=$(python3 -c "import json;print(','.join(json.load(open('$ROOT/config/zones.json')).get('$z',{}).get('usb') or []))" 2>/dev/null || true)
  IFS=',' read -ra D <<<"${usbs:-}"
  for d in "${D[@]}"; do [[ -n $d ]] && "$ROOT/scripts/usb-attach.sh" "$z" "$d" || true; done
}

[[ -n $TARGET && $TARGET != -h ]] || { echo "Usage: $0 <zone|all>"; zones | sed 's/^/  /'; exit 1; }
cd "$ROOT"
mapfile -t APP < <(zones)
if [[ $TARGET == all ]]; then
  start_one net; sleep 2
  for z in usb "${APP[@]}"; do [[ -n $z ]] && start_one "$z"; done
  exit 0
fi
for z in "${SYS[@]}" "${APP[@]}"; do
  [[ $TARGET == "$z" ]] && { start_one "$z"; exit 0; }
done
echo "Unknown: $TARGET" >&2; exit 1
