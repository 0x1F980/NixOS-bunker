#!/usr/bin/env bash
# Minimal clipboard mediation (Qubes-inspired, hackable).
#
# ALLOWED:
#   bunker-clip send <zone>           # host clipboard → zone (host clip KEPT)
#   bunker-clip copy <src> <dst>      # zone → zone via staging only (never on host clip)
#   bunker-clip clear                 # wipe staging + host clip NOW (manual)
#
# BLOCKED (no tools):
#   guest → host clipboard
#   SPICE/QEMU shared clipboard
#   silent VM↔VM / VM→host
#
# AUTO-CLEAR (default 30s, override anywhere below):
#   After send/copy: ZONE clipboard (+ staging file) wiped after TTL.
#   Host/global clipboard is NEVER auto-cleared by send/copy.
#
# Hack TTL (first match wins):
#   1) env BUNKER_CLIP_TTL=60
#   2) /etc/bunker/clipboard.conf  →  TTL=30
#   3) default 30
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZONE_PASS="${BUNKER_ZONE_PASS:-zone}"
STAGING_DIR="${BUNKER_CLIP_DIR:-/tmp/bunker-clip}"
mkdir -p "$STAGING_DIR"
chmod 700 "$STAGING_DIR"

# Load operator-tunable TTL
if [[ -z "${BUNKER_CLIP_TTL:-}" && -f /etc/bunker/clipboard.conf ]]; then
  # shellcheck disable=SC1091
  # TTL=NN in conf
  TTL_LINE="$(grep -E '^\s*TTL\s*=' /etc/bunker/clipboard.conf 2>/dev/null | tail -1 || true)"
  if [[ -n "$TTL_LINE" ]]; then
    BUNKER_CLIP_TTL="${TTL_LINE#*=}"
    BUNKER_CLIP_TTL="${BUNKER_CLIP_TTL// /}"
  fi
fi
TTL="${BUNKER_CLIP_TTL:-30}"

usage() {
  cat <<EOF
Usage:
  bunker-clip send <zone>         host clipboard → zone (host clip kept)
  bunker-clip copy <src> <dst>    zone → zone (mediated; not on host clip)
  bunker-clip clear               wipe staging + host clipboard now

Zone clipboard auto-clears after ${TTL}s (BUNKER_CLIP_TTL or /etc/bunker/clipboard.conf).
Host/global clipboard is kept on send/copy.
EOF
}

lookup_ip() {
  local name="$1"
  case "$name" in
    net) echo 10.0.0.1; return ;;
    usb) echo 10.0.0.2; return ;;
    vault) echo ""; return ;;
  esac
  if [[ -f /etc/bunker/zones.json ]]; then
    python3 -c "import json;z=json.load(open('/etc/bunker/zones.json'));print(z.get('$name',{}).get('ip',''))" 2>/dev/null && return
  fi
  if [[ -f "$ROOT/config/zones.json" ]]; then
    python3 -c "import json;z=json.load(open('$ROOT/config/zones.json'));print(z.get('$name',{}).get('ip',''))" 2>/dev/null && return
  fi
  echo ""
}

ssh_zone() {
  local ip="$1"
  shift
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
  if [[ -n "${BUNKER_ZONE_SSH_KEY:-}" && -f "${BUNKER_ZONE_SSH_KEY}" ]]; then
    ssh -i "$BUNKER_ZONE_SSH_KEY" -o BatchMode=yes "${ssh_opts[@]}" "zone@${ip}" "$@"
  elif command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$ZONE_PASS" ssh "${ssh_opts[@]}" -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no "zone@${ip}" "$@"
  else
    ssh -o BatchMode=yes "${ssh_opts[@]}" "zone@${ip}" "$@"
  fi
}

host_paste() {
  if command -v wl-paste >/dev/null 2>&1; then
    wl-paste -n || true
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard -o || true
  else
    echo "No wl-paste/xclip on host" >&2
    return 1
  fi
}

host_clear_clip() {
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy --clear 2>/dev/null || printf '' | wl-copy || true
  elif command -v xclip >/dev/null 2>&1; then
    printf '' | xclip -selection clipboard || true
  fi
}

# Wipe zone clipboard after TTL (does NOT touch host clipboard)
schedule_zone_clear() {
  local ip="$1"
  local zone="$2"
  (
    sleep "$TTL"
    ssh_zone "$ip" \
      'command -v wl-copy >/dev/null && wl-copy --clear 2>/dev/null || printf "" | wl-copy 2>/dev/null || true; rm -f /tmp/bunker-clipboard-in.txt' \
      2>/dev/null || true
    rm -f "$STAGING_DIR"/* 2>/dev/null || true
  ) >/dev/null 2>&1 &
  disown || true
  echo "zone '$zone' clipboard auto-clear in ${TTL}s (host/global clip kept)"
}

deliver_to() {
  local zone="$1"
  local file="$2"
  local ip
  ip="$(lookup_ip "$zone")"
  if [[ -z "$ip" ]]; then
    echo "ERROR: no IP for '$zone' (vault has no NIC)" >&2
    return 1
  fi
  ssh_zone "$ip" "cat > /tmp/bunker-clipboard-in.txt" <"$file"
  ssh_zone "$ip" 'command -v wl-copy >/dev/null && wl-copy < /tmp/bunker-clipboard-in.txt || true' || true
  local bytes
  bytes="$(wc -c <"$file" | tr -d ' ')"
  echo "OK → $zone ($ip) (${bytes} bytes)"
  schedule_zone_clear "$ip" "$zone"
}

cmd_clear() {
  rm -f "$STAGING_DIR"/* 2>/dev/null || true
  host_clear_clip
  echo "cleared staging + host clipboard (manual)"
  echo "BLOCKED paths remain blocked (no guest→host tool)."
}

cmd_send() {
  local zone="${1:?zone}"
  local f="$STAGING_DIR/send.$$"
  host_paste >"$f"
  if [[ ! -s "$f" ]]; then
    echo "host clipboard empty" >&2
    rm -f "$f"
    exit 1
  fi
  deliver_to "$zone" "$f"
  echo "host/global clipboard KEPT (not auto-cleared)"
  echo "REFUSING guest→host."
}

cmd_copy() {
  local src="${1:?src}"
  local dst="${2:?dst}"
  local sip dip f
  sip="$(lookup_ip "$src")"
  dip="$(lookup_ip "$dst")"
  if [[ -z "$sip" || -z "$dip" ]]; then
    echo "ERROR: need IPs for both zones (vault unsupported)" >&2
    exit 1
  fi
  f="$STAGING_DIR/copy.$$"
  # Pull from source — NEVER publish to host clipboard
  if ! ssh_zone "$sip" 'if command -v wl-paste >/dev/null; then wl-paste -n; elif test -f /tmp/bunker-clipboard-in.txt; then cat /tmp/bunker-clipboard-in.txt; fi' >"$f"; then
    echo "ERROR: could not read clipboard from $src" >&2
    exit 1
  fi
  if [[ ! -s "$f" ]]; then
    echo "ERROR: empty clipboard in $src" >&2
    exit 1
  fi
  deliver_to "$dst" "$f"
  ssh_zone "$sip" 'rm -f /tmp/bunker-clipboard-in.txt' || true
  echo "mediated $src → $dst (not on host clipboard; host/global kept)"
  echo "BLOCKED: guest→host, SPICE share, silent VM links"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    send) cmd_send "$@" ;;
    copy) cmd_copy "$@" ;;
    clear) cmd_clear ;;
    -h | --help | "") usage ;;
    *)
      echo "unknown: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
