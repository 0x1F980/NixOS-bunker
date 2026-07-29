#!/usr/bin/env bash
# One-way clipboard: HOST -> VM only (never guest -> host).
# Delivers via SSH to guest as zone@<vm-ip>.
# Usage: bunker-clipboard-send <vm> [text|-]
set -euo pipefail

VM="${1:-}"
TEXT="${2:-}"
ZONE_PASS="${BUNKER_ZONE_PASS:-zone}"

declare -A VM_IP=(
  [personal]=10.0.0.11
  [work]=10.0.0.12
  [browse]=10.0.0.13
  [sdr]=10.0.0.14
  [net]=10.0.0.1
  [usb]=10.0.0.2
  [vault]=
)

if [[ -z "$VM" ]]; then
  echo "Usage: $0 <vm> [text|-]"
  echo "  Sends host clipboard INTO the guest only."
  echo "  Guest→host clipboard is intentionally unsupported."
  exit 1
fi

if [[ "$VM" == "vault" ]]; then
  echo "vault has no NIC — use a shared virtio volume or USB for transfer." >&2
  exit 1
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

IP="${VM_IP[$VM]:-}"
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
