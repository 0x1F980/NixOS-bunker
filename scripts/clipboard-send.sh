#!/usr/bin/env bash
# One-way clipboard: HOST -> VM only (never guest -> host).
# Usage: bunker-clipboard-send <vm> [text|-]
set -euo pipefail

VM="${1:-}"
TEXT="${2:-}"
ZONE_PASS="${BUNKER_ZONE_PASS:-zone}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

lookup_ip() {
  local name="$1"
  case "$name" in
    net) echo 10.0.0.1; return ;;
    usb) echo 10.0.0.2; return ;;
    vault) echo ""; return ;;
  esac
  if [[ -f /etc/bunker/zones.tsv ]]; then
    awk -F'\t' -v z="$name" '$1==z {print $3; exit}' /etc/bunker/zones.tsv
    return
  fi
  # fallback examples from config/zones.nix defaults
  case "$name" in
    personal) echo 10.0.0.11 ;;
    work) echo 10.0.0.12 ;;
    browse) echo 10.0.0.13 ;;
    radio|sdr) echo 10.0.0.14 ;;
    *) echo "" ;;
  esac
}

if [[ -z "$VM" ]]; then
  echo "Usage: $0 <vm> [text|-]"
  echo "  Sends host clipboard INTO the guest only."
  exit 1
fi

if [[ "$VM" == "vault" ]]; then
  echo "vault has no NIC — use a shared virtio volume or USB for transfer." >&2
  exit 1
fi

if [[ "$VM" == "sdr" ]]; then
  VM=radio
fi

if [[ -z "$TEXT" ]]; then
  if command -v wl-paste >/dev/null 2>&1; then
    TEXT="$(wl-paste -n || true)"
  elif command -v xclip >/dev/null 2>&1; then
    TEXT="$(xclip -selection clipboard -o || true)"
  else
    echo "No wl-paste/xclip; pass text as arg 2 or '-'" >&2
    exit 1
  fi
elif [[ "$TEXT" == "-" ]]; then
  TEXT="$(cat)"
fi

IP="$(lookup_ip "$VM")"
OUT="/tmp/bunker-clip-out-${VM}.txt"
printf '%s' "$TEXT" >"$OUT"

ssh_to_zone() {
  local remote_cmd="$1"
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
  if [[ -n "${BUNKER_ZONE_SSH_KEY:-}" && -f "${BUNKER_ZONE_SSH_KEY}" ]]; then
    ssh -i "$BUNKER_ZONE_SSH_KEY" -o BatchMode=yes "${ssh_opts[@]}" "zone@${IP}" "$remote_cmd"
  elif command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$ZONE_PASS" ssh "${ssh_opts[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      "zone@${IP}" "$remote_cmd"
  else
    ssh -o BatchMode=yes "${ssh_opts[@]}" "zone@${IP}" "$remote_cmd"
  fi
}

if [[ -n "$IP" ]] && command -v ssh >/dev/null 2>&1; then
  if ssh_to_zone "cat > /tmp/bunker-clipboard-in.txt" <"$OUT"; then
    ssh_to_zone 'command -v wl-copy >/dev/null && wl-copy < /tmp/bunker-clipboard-in.txt || true' || true
    echo "Delivered host→${VM} clipboard (${#TEXT} bytes) via ssh zone@${IP}"
    echo "REFUSING any guest→host paste path."
    exit 0
  fi
fi

echo "Prepared host→${VM} payload at $OUT (${#TEXT} bytes)."
echo "Could not SSH to zone@${IP:-?}; copy manually into guest /tmp/bunker-clipboard-in.txt"
echo "REFUSING any guest→host paste path."
exit 1
