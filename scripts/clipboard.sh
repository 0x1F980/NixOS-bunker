#!/usr/bin/env bash
# Minimal clipboard mediation (Qubes-inspired, tiny).
#
# ALLOWED:
#   bunker-clip send <zone>           # host clipboard → zone
#   bunker-clip copy <src> <dst>      # zone → zone (via host tmp only; not left on host clip)
#   bunker-clip clear                 # wipe staging + host clipboard now
#
# BLOCKED (no tools for these):
#   guest → host clipboard
#   SPICE/QEMU shared clipboard
#   silent VM↔VM / VM→host
#
# Auto-clear: staging (+ optional host clip after send) wiped after BUNKER_CLIP_TTL sec (default 45).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZONE_PASS="${BUNKER_ZONE_PASS:-zone}"
TTL="${BUNKER_CLIP_TTL:-45}"
STAGING_DIR="${BUNKER_CLIP_DIR:-/tmp/bunker-clip}"
mkdir -p "$STAGING_DIR"
chmod 700 "$STAGING_DIR"

usage() {
  cat <<EOF
Usage:
  bunker-clip send <zone>         host clipboard → zone
  bunker-clip copy <src> <dst>    zone → zone (mediated)
  bunker-clip clear               wipe staging + host clipboard
EOF
}

lookup_ip() {
  local name="$1"
  case "$name" in
    net) echo 10.0.0.1; return ;;
    usb) echo 10.0.0.2; return ;;
    vault) echo ""; return ;;
    sdr) name=radio ;;
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

schedule_clear() {
  local also_host="${1:-0}"
  (
    sleep "$TTL"
    rm -f "$STAGING_DIR"/* 2>/dev/null || true
    if [[ "$also_host" == "1" ]]; then
      host_clear_clip
    fi
  ) >/dev/null 2>&1 &
  disown || true
  echo "auto-clear in ${TTL}s (staging${also_host:+ + host clip})"
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
}

cmd_clear() {
  rm -f "$STAGING_DIR"/* 2>/dev/null || true
  host_clear_clip
  echo "cleared staging + host clipboard"
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
  echo "REFUSING guest→host."
  schedule_clear 1
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
  # Pull from source zone clipboard or fallback file — NEVER publish to host clipboard
  if ! ssh_zone "$sip" 'if command -v wl-paste >/dev/null; then wl-paste -n; elif test -f /tmp/bunker-clipboard-in.txt; then cat /tmp/bunker-clipboard-in.txt; fi' >"$f"; then
    echo "ERROR: could not read clipboard from $src" >&2
    exit 1
  fi
  if [[ ! -s "$f" ]]; then
    echo "ERROR: empty clipboard in $src" >&2
    exit 1
  fi
  deliver_to "$dst" "$f"
  # wipe source staging hint inside src (optional hygiene)
  ssh_zone "$sip" 'rm -f /tmp/bunker-clipboard-in.txt' || true
  echo "mediated $src → $dst (not placed on host clipboard)"
  echo "BLOCKED: guest→host, SPICE share, silent VM links"
  schedule_clear 0
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
