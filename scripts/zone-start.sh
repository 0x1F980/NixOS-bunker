#!/usr/bin/env bash
# Start bunker microVM zones on-demand.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEM_ZONES=(net usb vault)
TARGET="${1:-}"

usage() {
  echo "Usage: $0 [all|net|usb|vault|<app-zone>]"
  echo "  App zones come from config/zones.nix (see /etc/bunker/zones.tsv on host)."
  echo "  Runs: nix run \"\$ROOT#zone-<name>\"  (native arch: x86_64 or aarch64)"
}

list_app_zones() {
  if [[ -f /etc/bunker/zones.tsv ]]; then
    cut -f1 /etc/bunker/zones.tsv
  elif [[ -f "$ROOT/config/zones.nix" ]] && command -v nix >/dev/null 2>&1; then
    nix --extra-experimental-features "nix-command flakes" eval --raw \
      --impure --expr "let z=import $ROOT/config/zones.nix; in builtins.concatStringsSep \" \" (builtins.attrNames z)" 2>/dev/null \
      | tr ' ' '\n'
  else
    # fallback examples
    printf '%s\n' personal work browse radio
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
  ensure_bridge
  echo "==> starting zone '$z' via nix run .#zone-$z"
  if command -v nix >/dev/null 2>&1; then
    nix run "$ROOT#zone-$z" &
    echo "started pid $!"
    sleep 2
    ensure_bridge
    # Attach USB defaults from zones.json
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
    fi
  elif systemctl list-unit-files "microvm@$z.service" >/dev/null 2>&1; then
    systemctl start "microvm@$z.service"
  else
    echo "ERROR: nix not found and no microvm@$z.service" >&2
    exit 1
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
