# Shared helpers for bunker operator scripts (usb / clipboard / zone-term / bunker-zone).
# Source:  # shellcheck source=lib-common.sh
#          source "$(dirname "$0")/lib-common.sh"

bunker_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Resolve zones.json: BUNKER_ZONES_JSON → checkout → ~/nixos-bunker → /etc/bunker
bunker_zones_json() {
  if [[ -n "${BUNKER_ZONES_JSON:-}" && -f "${BUNKER_ZONES_JSON}" ]]; then
    echo "$BUNKER_ZONES_JSON"
    return
  fi
  local root="${BUNKER_ROOT:-$(bunker_repo_root)}"
  local p
  for p in "$root/config/zones.json" "$HOME/nixos-bunker/config/zones.json" /etc/bunker/zones.json; do
    if [[ -f "$p" ]]; then
      echo "$p"
      return
    fi
  done
  echo "$root/config/zones.json"
}

# net/usb fixed; vault empty; else zones.json ip. No legacy aliases.
bunker_zone_ip() {
  local name="$1"
  case "$name" in
    net) echo 10.0.0.1; return ;;
    usb) echo 10.0.0.2; return ;;
    voice) echo 10.0.0.3; return ;;
    vault) echo ""; return ;;
  esac
  local zj
  zj="$(bunker_zones_json)"
  [[ -f "$zj" ]] || {
    echo ""
    return
  }
  python3 -c "import json;z=json.load(open('$zj'));print(z.get('$name',{}).get('ip',''))" 2>/dev/null || echo ""
}

# SSH into zone@IP. Optional leading ssh flags (e.g. -t) before IP.
#   bunker_ssh_zone 10.0.0.11 'uname -a'
#   bunker_ssh_zone -t 10.0.0.11 'bash -l'
bunker_ssh_zone() {
  local extra=()
  while [[ "${1:-}" == -* ]]; do
    extra+=("$1")
    shift
  done
  local ip="${1:?ip}"
  shift
  local pass="${BUNKER_ZONE_PASS:-zone}"
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
  if [[ -n "${BUNKER_ZONE_SSH_KEY:-}" && -f "${BUNKER_ZONE_SSH_KEY}" ]]; then
    ssh "${extra[@]}" -i "$BUNKER_ZONE_SSH_KEY" "${ssh_opts[@]}" "zone@${ip}" "$@"
  elif command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$pass" ssh "${extra[@]}" "${ssh_opts[@]}" -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no "zone@${ip}" "$@"
  else
    ssh "${extra[@]}" "${ssh_opts[@]}" "zone@${ip}" "$@"
  fi
}
