#!/usr/bin/env bash
# Mediated clipboard: send|copy|clear. Host→zone / zone→zone only. TTL clears zone clip.
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
STAGING="${BUNKER_CLIP_DIR:-/tmp/bunker-clip}"; mkdir -p "$STAGING"; chmod 700 "$STAGING"
if [[ -z ${BUNKER_CLIP_TTL:-} && -f /etc/bunker/clipboard.conf ]]; then
  BUNKER_CLIP_TTL=$(grep -E '^\s*TTL\s*=' /etc/bunker/clipboard.conf | tail -1 | sed 's/.*=\s*//' | tr -d ' ' || true)
fi
TTL=${BUNKER_CLIP_TTL:-30}

host_paste() {
  if command -v wl-paste >/dev/null; then wl-paste -n || true
  elif command -v xclip >/dev/null; then xclip -selection clipboard -o || true
  else echo "no wl-paste/xclip" >&2; return 1; fi
}
host_clear() {
  command -v wl-copy >/dev/null && { wl-copy --clear 2>/dev/null || printf '' | wl-copy; } || true
  command -v xclip >/dev/null && printf '' | xclip -selection clipboard || true
}
schedule_clear() {
  local ip=$1
  ( sleep "$TTL"
    bunker_ssh_zone "$ip" 'command -v wl-copy >/dev/null && wl-copy --clear; rm -f /tmp/bunker-clipboard-in.txt' 2>/dev/null || true
    rm -f "$STAGING"/* 2>/dev/null || true
  ) >/dev/null 2>&1 & disown || true
}
deliver() {
  local zone=$1 file=$2 ip; ip=$(bunker_zone_ip "$zone")
  [[ -n $ip ]] || { echo "no IP for $zone" >&2; return 1; }
  bunker_ssh_zone "$ip" "cat > /tmp/bunker-clipboard-in.txt" <"$file"
  bunker_ssh_zone "$ip" 'command -v wl-copy >/dev/null && wl-copy < /tmp/bunker-clipboard-in.txt || true' || true
  echo "OK → $zone ($ip)"; schedule_clear "$ip"
}

case "${1:-}" in
  send)
    f=$STAGING/send.$$; host_paste >"$f"
    [[ -s $f ]] || { echo "empty clipboard" >&2; rm -f "$f"; exit 1; }
    deliver "${2:?}" "$f"
    ;;
  copy)
    sip=$(bunker_zone_ip "${2:?}"); dip=$(bunker_zone_ip "${3:?}")
    [[ -n $sip && -n $dip ]] || { echo "need IPs" >&2; exit 1; }
    f=$STAGING/copy.$$
    bunker_ssh_zone "$sip" 'wl-paste -n 2>/dev/null || cat /tmp/bunker-clipboard-in.txt 2>/dev/null' >"$f" || true
    [[ -s $f ]] || { echo "empty src" >&2; exit 1; }
    deliver "${3}" "$f"
    bunker_ssh_zone "$sip" 'rm -f /tmp/bunker-clipboard-in.txt' || true
    ;;
  clear) rm -f "$STAGING"/*; host_clear; echo "cleared";;
  *) echo "Usage: bunker-clip send <z>|copy <a> <b>|clear"; exit 1;;
esac
