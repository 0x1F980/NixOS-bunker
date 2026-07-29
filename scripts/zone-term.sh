#!/usr/bin/env bash
# Open a colored shell into a zone (SSH) — Qubes-like visual separation.
# Usage: bunker-term <zone>
set -euo pipefail

ZONE="${1:-}"
ZONE_PASS="${BUNKER_ZONE_PASS:-zone}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Prefer checkout; on host /etc/bunker/scripts → look beside zones.json
if [[ -z "${BUNKER_ZONES_JSON:-}" ]]; then
  for p in \
    "$ROOT/config/zones.json" \
    "$HOME/nixos-bunker/config/zones.json" \
    /etc/bunker/zones.json
  do
    if [[ -f "$p" ]]; then
      ZONES_JSON="$p"
      break
    fi
  done
else
  ZONES_JSON="$BUNKER_ZONES_JSON"
fi
ZONES_JSON="${ZONES_JSON:-$ROOT/config/zones.json}"
COLORS_NIX="$ROOT/config/colors.nix"

if [[ -z "$ZONE" ]]; then
  echo "Usage: $0 <zone>"
  exit 1
fi

lookup() {
  case "$ZONE" in
    net) echo 10.0.0.1; echo black; return ;;
    usb) echo 10.0.0.2; echo purple; return ;;
    vault)
      echo "vault has no NIC — use console/microvm attach, not SSH" >&2
      exit 1
      ;;
  esac
  python3 - "$ZONES_JSON" "$ZONE" <<'PY'
import json, sys
z = json.load(open(sys.argv[1]))
n = sys.argv[2]
if n == "sdr":
    n = "radio"
if n not in z:
    raise SystemExit(f"unknown zone: {n}")
c = z[n]
print(c["ip"])
print(c.get("color", "gray"))
PY
}

mapfile -t info < <(lookup)
IP="${info[0]}"
COLOR="${info[1]}"

# ANSI map (fallback)
declare -A ANSI=(
  [red]=31 [orange]=33 [yellow]=93 [green]=32
  [blue]=34 [purple]=35 [black]=90 [gray]=37
)
declare -A BG=(
  [red]='#2a0000' [orange]='#2a1500' [yellow]='#2a2a00' [green]='#002a00'
  [blue]='#00152a' [purple]='#1a002a' [black]='#111111' [gray]='#1a1a1a'
)
declare -A FG=(
  [red]='#cc0000' [orange]='#f57900' [yellow]='#edd400' [green]='#73d216'
  [blue]='#3465a4' [purple]='#75507b' [black]='#2e3436' [gray]='#888a85'
)

A="${ANSI[$COLOR]:-37}"
B="${BG[$COLOR]:-#1a1a1a}"
F="${FG[$COLOR]:-#cccccc}"

echo "→ zone=$ZONE color=$COLOR ip=$IP"

# Tint local terminal first (host side)
printf '\033]11;%s\007' "$B" 2>/dev/null || true
printf '\033]10;%s\007' "$F" 2>/dev/null || true

REMOTE_INIT=$(
  cat <<EOF
printf '\\033]11;$B\\007' 2>/dev/null || true
printf '\\033]10;$F\\007' 2>/dev/null || true
export BUNKER_ZONE='$ZONE' BUNKER_ZONE_COLOR='$COLOR'
export PS1='\\[\\e[${A}m\\][$ZONE]\\[\\e[0m\\] \\u@\\h:\\w\\$ '
exec bash -l
EOF
)

ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
if [[ -n "${BUNKER_ZONE_SSH_KEY:-}" && -f "${BUNKER_ZONE_SSH_KEY}" ]]; then
  exec ssh -t -i "$BUNKER_ZONE_SSH_KEY" "${ssh_opts[@]}" "zone@${IP}" "$REMOTE_INIT"
elif command -v sshpass >/dev/null 2>&1; then
  exec sshpass -p "$ZONE_PASS" ssh -t "${ssh_opts[@]}" -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no "zone@${IP}" "$REMOTE_INIT"
else
  exec ssh -t "${ssh_opts[@]}" "zone@${IP}" "$REMOTE_INIT"
fi
