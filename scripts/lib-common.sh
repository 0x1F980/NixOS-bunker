# Shared helpers for bunker scripts.
bunker_repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

bunker_public_zones_json() {
  [[ -n ${BUNKER_ZONES_JSON:-} && -f $BUNKER_ZONES_JSON ]] && { echo "$BUNKER_ZONES_JSON"; return; }
  local root=${BUNKER_ROOT:-$(bunker_repo_root)} p
  # Mutable SoT on installed host first (etc is nix-store immutable)
  for p in /var/lib/bunker/zones.json \
    "$root/config/zones.json" \
    "$HOME/NixOS-bunker/config/zones.json" \
    "$HOME/nixos-bunker/config/zones.json" \
    /etc/bunker/zones.json; do
    [[ -f $p ]] && { echo "$p"; return; }
  done
  echo "$root/config/zones.json"
}

# Prefer runtime merge (public ∪ unlocked hidden); else public only.
bunker_zones_json() {
  if [[ -f /run/bunker/zones-merged.json ]]; then
    echo /run/bunker/zones-merged.json
    return
  fi
  bunker_public_zones_json
}

bunker_slots_json() {
  local root=${BUNKER_ROOT:-$(bunker_repo_root)} p
  for p in "$root/config/slots.json" "$HOME/NixOS-bunker/config/slots.json" /etc/bunker/slots.json; do
    [[ -f $p ]] && { echo "$p"; return; }
  done
  echo "$root/config/slots.json"
}

bunker_merged_zones_file() { echo /run/bunker/zones-merged.json; }

bunker_zone_ip() {
  case "$1" in net) echo 10.0.0.1; return;; usb) echo 10.0.0.2; return;; esac
  python3 -c "import json;print(json.load(open('$(bunker_zones_json)')).get('$1',{}).get('ip',''))" 2>/dev/null || echo
}

# Resolve friendly name → microVM unit / flake package name (slot id or same name).
bunker_zone_runtime_id() {
  python3 -c "
import json,sys
z=json.load(open('$(bunker_zones_json)')).get('$1') or {}
print(z.get('slot') or '$1')
" 2>/dev/null
}

bunker_zone_is_hidden() {
  python3 -c "
import json,sys
z=json.load(open('$(bunker_zones_json)')).get('$1') or {}
sys.exit(0 if z.get('invisible') or z.get('slot') else 1)
" 2>/dev/null
}

bunker_zone_is_iso() {
  python3 -c "
import json,sys
z=json.load(open('$(bunker_zones_json)')).get('$1') or {}
sys.exit(0 if (z.get('template')=='iso' or bool((z.get('iso') or '').strip())) else 1)
" 2>/dev/null
}

# netVM / usbVM brokers (also role=broker in zones.json)
bunker_zone_is_broker() {
  case "$1" in net|usb) return 0;; esac
  python3 -c "
import json,sys
z=json.load(open('$(bunker_zones_json)')).get('$1') or {}
sys.exit(0 if z.get('role')=='broker' else 1)
" 2>/dev/null
}

bunker_zone_is_disposable() {
  python3 -c "
import json,sys
z=json.load(open('$(bunker_zones_json)')).get('$1') or {}
sys.exit(0 if (z.get('kind')=='disposable' or z.get('disposable') is True) else 1)
" 2>/dev/null
}

bunker_qmp_sock() {
  local vm=$1 cand
  for cand in "/run/microvm/${vm}.sock" "/var/lib/microvms/$vm/sock" "/var/lib/microvms/$vm/qemu.sock"; do
    [[ -S $cand ]] && { echo "$cand"; return 0; }
  done
  return 1
}

bunker_qmp() {
  local sock=$1 cmd=$2
  { sleep 0.05; printf '%s\n' '{"execute":"qmp_capabilities"}'; sleep 0.05; printf '%s\n' "$cmd"; } | socat - UNIX-CONNECT:"$sock"
}

bunker_ssh_zone() {
  local extra=()
  while [[ ${1:-} == -* ]]; do extra+=("$1"); shift; done
  local ip=${1:?}; shift
  local pass=${BUNKER_ZONE_PASS:-zone}
  local opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
  if [[ -n ${BUNKER_ZONE_SSH_KEY:-} && -f $BUNKER_ZONE_SSH_KEY ]]; then
    ssh "${extra[@]}" -i "$BUNKER_ZONE_SSH_KEY" "${opts[@]}" "zone@$ip" "$@"
  elif command -v sshpass >/dev/null; then
    sshpass -p "$pass" ssh "${extra[@]}" "${opts[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no "zone@$ip" "$@"
  else
    ssh "${extra[@]}" "${opts[@]}" "zone@$ip" "$@"
  fi
}
