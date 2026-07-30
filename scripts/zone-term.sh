#!/usr/bin/env bash
# Colored SSH into a zone. Usage: bunker-term <zone>
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
ZONE="${1:?zone}"
bunker_zone_is_iso "$ZONE" && { echo "ISO zone — use QEMU window" >&2; exit 1; }
IP=$(bunker_zone_ip "$ZONE")
[[ -n $IP ]] || { echo "no IP" >&2; exit 1; }
COLOR=$(python3 -c "import json;print(json.load(open('$(bunker_zones_json)')).get('$ZONE',{}).get('color','gray'))" 2>/dev/null || echo gray)
case $ZONE in net) COLOR=black;; usb) COLOR=purple;; esac
declare -A A=( [red]=31 [orange]=33 [yellow]=93 [green]=32 [blue]=34 [purple]=35 [black]=90 [gray]=37 )
declare -A BG=( [red]='#2a0000' [orange]='#2a1500' [yellow]='#2a2a00' [green]='#002a00' [blue]='#00152a' [purple]='#1a002a' [black]='#111111' [gray]='#1a1a1a' )
declare -A FG=( [red]='#cc0000' [orange]='#f57900' [yellow]='#edd400' [green]='#73d216' [blue]='#3465a4' [purple]='#75507b' [black]='#2e3436' [gray]='#888a85' )
echo "→ $ZONE $COLOR $IP"
printf '\033]11;%s\007' "${BG[$COLOR]:-#1a1a1a}" 2>/dev/null || true
printf '\033]10;%s\007' "${FG[$COLOR]:-#ccc}" 2>/dev/null || true
exec bunker_ssh_zone -t "$IP" "export BUNKER_ZONE='$ZONE' BUNKER_ZONE_COLOR='$COLOR'; printf '\\033]11;${BG[$COLOR]:-#1a1a1a}\\007' 2>/dev/null; printf '\\033]10;${FG[$COLOR]:-#ccc}\\007' 2>/dev/null; export PS1='\\[\\e[${A[$COLOR]:-37}m\\][$ZONE]\\[\\e[0m\\] \\u@\\h:\\w\\$ '; exec bash -l"
