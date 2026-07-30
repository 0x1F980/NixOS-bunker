# Shufflecake helpers (sourced by bunker-sflc / panic).
bunker_sflc_conf() {
  [[ -f /etc/bunker/shufflecake.json ]] && echo /etc/bunker/shufflecake.json \
    || echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/shufflecake.json"
}
bunker_deniable_json() {
  [[ -n ${BUNKER_ZONES_JSON:-} && -f $BUNKER_ZONES_JSON ]] && { echo "$BUNKER_ZONES_JSON"; return; }
  local root=${BUNKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)} p
  for p in "$root/config/zones.json" "$HOME/NixOS-bunker/config/zones.json" /etc/bunker/zones.json; do
    [[ -f $p ]] && { echo "$p"; return; }
  done
  echo "$root/config/zones.json"
}
bunker_sflc_get() {
  python3 -c "import json;print(json.load(open('$(bunker_sflc_conf)')).get('$1','') or '')"
}
bunker_sflc_mount_root() { bunker_sflc_get mount_root; }
bunker_sflc_device() { bunker_sflc_get device; }
bunker_sflc_mode() {
  local m device; m=$(bunker_sflc_get mode); device=$(bunker_sflc_device)
  if [[ $m == shufflecake ]]; then echo shufflecake
  elif [[ $m == stub ]]; then echo stub
  elif [[ -n $device ]] && command -v shufflecake >/dev/null; then echo shufflecake
  else echo stub; fi
}
bunker_unlocked_layers_file() { echo /run/bunker/unlocked-layers; }
bunker_visible_zones_file() { echo /run/bunker/visible-zones.json; }
