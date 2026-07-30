#!/usr/bin/env bash
# Start bunker microVM zones on-demand (NixOS) or ISO/HVM zones (QEMU).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-common.sh
source "$ROOT/scripts/lib-common.sh"
SYSTEM_ZONES=(net usb voice vault)
TARGET="${1:-}"

usage() {
  echo "Usage: $0 [all|net|usb|vault|<app-zone>]"
  echo "  App zones come from config/zones.nix (see /etc/bunker/zones.tsv on host)."
  echo "  NixOS: nix run \"\$ROOT#zone-<name>\""
  echo "  ISO/HVM (template=iso): scripts/iso-run.sh <name>"
}

list_app_zones() {
  if [[ -f /etc/bunker/zones.tsv ]]; then
    cut -f1 /etc/bunker/zones.tsv
  elif [[ -f "$ROOT/config/zones.json" ]] && command -v python3 >/dev/null; then
    python3 -c "import json;print('\\n'.join(json.load(open('$ROOT/config/zones.json'))))" 2>/dev/null
  else
    printf '%s\n' personal work browse radio
  fi
  # Unlocked deniable VMs (whole zones)
  if [[ -f /run/bunker/visible-zones.json ]] && command -v python3 >/dev/null; then
    python3 -c "import json;print('\\n'.join(json.load(open('/run/bunker/visible-zones.json'))))" 2>/dev/null || true
  fi
}

invisible_blocked() {
  local z="$1"
  local zj="$ROOT/config/zones.json"
  [[ -f /etc/bunker/zones.json ]] && zj=/etc/bunker/zones.json
  [[ -f "$zj" ]] || return 1
  python3 - "$zj" "$z" <<'PY'
import json, sys
z = json.load(open(sys.argv[1]))
n = sys.argv[2]
c = z.get(n)
if not c or not c.get("invisible"):
    raise SystemExit(1)
raise SystemExit(0)
PY
}

require_invisible_unlocked() {
  local z="$1"
  if invisible_blocked "$z"; then
    if [[ -f /run/bunker/visible-zones.json ]] && python3 -c "import json,sys;sys.exit(0 if sys.argv[1] in json.load(open('/run/bunker/visible-zones.json')) else 1)" "$z" 2>/dev/null; then
      return 0
    fi
    echo "ERROR: invisible zone '$z' is locked — unlock via: bunker  (zones) / bunker-sflc unlock <layer>" >&2
    exit 1
  fi
}

ensure_bridge() {
  if command -v ip >/dev/null 2>&1; then
    ip link add name br-bunker type bridge 2>/dev/null || true
    ip link set br-bunker up 2>/dev/null || true
    ip addr replace 10.0.0.254/24 dev br-bunker 2>/dev/null || true
  fi
  if systemctl list-unit-files bunker-bridge-attach.service >/dev/null 2>&1; then
    systemctl start bunker-bridge-attach.service 2>/dev/null || true
  fi
}

start_one() {
  local z="$1"
  require_invisible_unlocked "$z"
  ensure_bridge
  if bunker_zone_is_iso "$z"; then
    echo "==> starting ISO/HVM zone '$z' via iso-run.sh"
    "$ROOT/scripts/iso-run.sh" "$z" &
    echo "started pid $!"
    sleep 2
    ensure_bridge
  else
    echo "==> starting zone '$z' via nix run .#zone-$z"
    if command -v nix >/dev/null 2>&1; then
      nix run "$ROOT#zone-$z" &
      echo "started pid $!"
      sleep 2
      ensure_bridge
    elif systemctl list-unit-files "microvm@$z.service" >/dev/null 2>&1; then
      systemctl start "microvm@$z.service"
    else
      echo "ERROR: nix not found and no microvm@$z.service" >&2
      exit 1
    fi
  fi
  # Attach USB defaults from zones.json (NixOS usbip or ISO direct QMP)
  if [[ -f /etc/bunker/zones.tsv ]] || [[ -f "$ROOT/config/zones.json" ]]; then
    local usbs=""
    if [[ -f /etc/bunker/zones.tsv ]]; then
      usbs="$(awk -F'\t' -v n="$z" '$1==n {print $8}' /etc/bunker/zones.tsv || true)"
    fi
    if [[ -z "$usbs" || "$usbs" == "-" ]] && command -v python3 >/dev/null; then
      usbs="$(python3 -c "import json;z=json.load(open('$ROOT/config/zones.json'));print(','.join(z.get('$z',{}).get('usb') or []))" 2>/dev/null || true)"
    fi
    if [[ -n "$usbs" && "$usbs" != "-" ]]; then
      IFS=',' read -ra DEVS <<<"$usbs"
      for d in "${DEVS[@]}"; do
        [[ -z "$d" ]] && continue
        echo "==> usb default attach $d -> $z"
        "$ROOT/scripts/usb-attach.sh" "$z" "$d" || echo "WARN: usb attach $d failed (VM may still be booting)"
      done
    fi
    # Voice anonymizer — NixOS zones only (ISO guests rarely speak Pulse/ssh)
    if ! bunker_zone_is_iso "$z"; then
      local von=""
      if command -v python3 >/dev/null; then
        von="$(python3 -c "
import json
z=json.load(open('$ROOT/config/zones.json'))
v=z.get('$z',{}).get('voice', False)
print('1' if v in (True,'on','true','1','anon','chimera') else '0')
" 2>/dev/null || true)"
        if [[ -z "$von" && -f /etc/bunker/zones.json ]]; then
          von="$(python3 -c "
import json
z=json.load(open('/etc/bunker/zones.json'))
v=z.get('$z',{}).get('voice', False)
print('1' if v in (True,'on','true','1','anon','chimera') else '0')
" 2>/dev/null || true)"
        fi
      fi
      if [[ "$von" == "1" ]]; then
        echo "==> voice=on → voiceVM anonymized mic"
        "$ROOT/scripts/voice-attach.sh" "$z" || echo "WARN: voice attach failed (is voiceVM up?)"
      fi
    fi
  fi
}

if [[ -z "$TARGET" || "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
  usage
  echo "App zones:"
  list_app_zones | sed 's/^/  /'
  exit 1
fi

cd "$ROOT"
mapfile -t APP_ZONES < <(list_app_zones)

if [[ "$TARGET" == "all" ]]; then
  start_one net
  sleep 2
  for z in usb vault "${APP_ZONES[@]}"; do
    [[ -n "$z" ]] || continue
    start_one "$z"
  done
  exit 0
fi

for z in "${SYSTEM_ZONES[@]}" "${APP_ZONES[@]}"; do
  if [[ "$TARGET" == "$z" ]]; then
    start_one "$z"
    exit 0
  fi
done

echo "Unknown zone: $TARGET" >&2
usage
exit 1
