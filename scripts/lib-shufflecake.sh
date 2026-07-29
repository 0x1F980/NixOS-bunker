# Shufflecake / deniable-layer helpers for bunker (sourced by bunker-sflc.sh / panic).
# shellcheck shell=bash

bunker_sflc_conf() {
  if [[ -f /etc/bunker/shufflecake.json ]]; then
    echo /etc/bunker/shufflecake.json
  else
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/shufflecake.json"
  fi
}

bunker_deniable_json() {
  if [[ -n "${BUNKER_DENIABLE_JSON:-}" && -f "${BUNKER_DENIABLE_JSON}" ]]; then
    echo "$BUNKER_DENIABLE_JSON"
    return
  fi
  local root="${BUNKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  for p in "$root/config/deniable-zones.json" "$HOME/nixos-bunker/config/deniable-zones.json" /etc/bunker/deniable-zones.json; do
    [[ -f "$p" ]] && {
      echo "$p"
      return
    }
  done
  echo "$root/config/deniable-zones.json"
}

bunker_sflc_get() {
  local key="$1"
  python3 - "$key" "$(bunker_sflc_conf)" <<'PY'
import json, sys
k, path = sys.argv[1], sys.argv[2]
c = json.load(open(path))
v = c.get(k, "")
print(v if v is not None else "")
PY
}

bunker_sflc_mount_root() {
  bunker_sflc_get mount_root
}

bunker_sflc_device() {
  bunker_sflc_get device
}

bunker_sflc_mode() {
  local m device
  m="$(bunker_sflc_get mode)"
  device="$(bunker_sflc_device)"
  if [[ "$m" == "shufflecake" ]]; then
    echo shufflecake
  elif [[ "$m" == "stub" ]]; then
    echo stub
  elif [[ -n "$device" ]] && command -v shufflecake >/dev/null 2>&1; then
    echo shufflecake
  else
    echo stub
  fi
}

bunker_unlocked_layers_file() {
  echo /run/bunker/unlocked-layers
}

bunker_visible_zones_file() {
  echo /run/bunker/visible-zones.json
}
