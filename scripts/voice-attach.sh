#!/usr/bin/env bash
# Point an app zone at voiceVM anonymized mic (1→many).
# Usage: bunker-voice-attach <zone>   # sets pulse on zone → 10.0.0.3
#        bunker-voice-detach <zone>
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

VOICE_IP="10.0.0.3"
ZONE="${1:-}"
OP="$(basename "$0")"
[[ "$OP" == *detach* ]] && MODE=detach || MODE=attach

if [[ -z "$ZONE" ]]; then
  echo "Usage: bunker-voice-attach|detach <zone>"
  exit 1
fi

IP="$(bunker_zone_ip "$ZONE")"
[[ -n "$IP" ]] || {
  echo "ERROR: unknown zone $ZONE" >&2
  exit 1
}
if [[ "$ZONE" == "voice" || "$ZONE" == "net" || "$ZONE" == "usb" || "$ZONE" == "vault" ]]; then
  echo "ERROR: attach to an app zone, not $ZONE" >&2
  exit 1
fi

if [[ "$MODE" == "attach" ]]; then
  echo "==> $ZONE: Pulse → voiceVM $VOICE_IP (anonymized mic)"
  bunker_ssh_zone "$IP" "mkdir -p ~/.config && printf 'default-server = tcp:${VOICE_IP}:4713\n' > ~/.config/pulse/client.conf && export PULSE_SERVER=tcp:${VOICE_IP}:4713; echo OK pulse→${VOICE_IP}" || true
  # Persist for future shells
  bunker_ssh_zone "$IP" "grep -q BUNKER_VOICE /etc/environment 2>/dev/null || echo 'PULSE_SERVER=tcp:${VOICE_IP}:4713' | sudo tee -a /etc/environment >/dev/null" || true
  echo "OK: $ZONE uses anonymized mic from voiceVM (Chimera/sox). Start voice: bunker-zone-start voice"
else
  echo "==> $ZONE: clear Pulse tunnel"
  bunker_ssh_zone "$IP" "rm -f ~/.config/pulse/client.conf; sudo sed -i '/PULSE_SERVER=tcp:10.0.0.3/d' /etc/environment 2>/dev/null || true"
  echo "OK: detached $ZONE from voiceVM"
fi
