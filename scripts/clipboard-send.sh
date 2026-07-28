#!/usr/bin/env bash
# One-way clipboard: HOST -> VM only. Never read guest clipboard into host.
# Usage: bunker-clipboard-send <vm> [text|-]
set -euo pipefail

VM="${1:-}"
TEXT="${2:-}"

if [[ -z "$VM" ]]; then
  echo "Usage: $0 <vm> [text|-]"
  echo "  Sends host clipboard (or text) INTO the guest only."
  echo "  Guest→host clipboard is intentionally unsupported."
  exit 1
fi

if [[ -z "$TEXT" ]]; then
  if command -v wl-paste >/dev/null 2>&1; then
    TEXT="$(wl-paste -n || true)"
  elif command -v xclip >/dev/null 2>&1; then
    TEXT="$(xclip -selection clipboard -o || true)"
  else
    echo "No clipboard tool (wl-paste/xclip); pass text as arg 2 or stdin with -" >&2
    exit 1
  fi
elif [[ "$TEXT" == "-" ]]; then
  TEXT="$(cat)"
fi

# Deliver via SSH to guest if available, else print instructions
# microvms often use vsock/ssh — placeholder path:
TARGET_FILE="/tmp/bunker-clipboard-in.txt"
echo "$TEXT" >"/tmp/bunker-clip-out-${VM}.txt"
echo "Prepared host→${VM} clipboard payload (${#TEXT} bytes)."
echo "Inject into guest (example):"
echo "  microvm -c $VM  # then copy /tmp/bunker-clip-out-${VM}.txt into guest $TARGET_FILE"
echo "REFUSING any guest→host paste path."
