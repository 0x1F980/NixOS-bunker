#!/usr/bin/env bash
# Shufflecake deniable layers: unlock/lock whole zone-VMs; refresh GNOME visibility.
# Usage:
#   bunker-sflc status
#   bunker-sflc unlock <layer>          # reads passphrase from stdin
#   bunker-sflc lock <layer|all>
#   bunker-sflc sync-visible            # rewrite /run/bunker/visible-zones.json + XDG launchers
#   bunker-sflc path <zone>             # print microvm data dir when unlocked
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
# shellcheck source=lib-shufflecake.sh
source "$(dirname "$0")/lib-shufflecake.sh"

ensure_runtime() {
  mkdir -p /run/bunker/xdg/applications "$(bunker_sflc_mount_root)" /var/lib/bunker/sflc-keys
  chmod 700 /var/lib/bunker/sflc-keys 2>/dev/null || true
  touch "$(bunker_unlocked_layers_file)" 2>/dev/null || true
}

layer_dir() {
  echo "$(bunker_sflc_mount_root)/layer$1"
}

is_unlocked() {
  local layer="$1"
  [[ -f "$(bunker_unlocked_layers_file)" ]] || return 1
  grep -qx "$layer" "$(bunker_unlocked_layers_file)" 2>/dev/null
}

mark_unlocked() {
  local layer="$1"
  ensure_runtime
  grep -qx "$layer" "$(bunker_unlocked_layers_file)" 2>/dev/null || echo "$layer" >>"$(bunker_unlocked_layers_file)"
}

unmark_unlocked() {
  local layer="$1"
  local f
  f="$(bunker_unlocked_layers_file)"
  [[ -f "$f" ]] || return 0
  grep -vx "$layer" "$f" >"$f.tmp" 2>/dev/null || true
  mv "$f.tmp" "$f"
}

cmd_status() {
  ensure_runtime
  echo "mode=$(bunker_sflc_mode) device=$(bunker_sflc_device) mount=$(bunker_sflc_mount_root)"
  echo "zones=$(bunker_deniable_json)"
  echo -n "unlocked_layers: "
  if [[ -s "$(bunker_unlocked_layers_file)" ]]; then
    tr '\n' ' ' <"$(bunker_unlocked_layers_file)"
    echo
  else
    echo "(none)"
  fi
  echo "visible: $(bunker_visible_zones_file)"
  [[ -f "$(bunker_visible_zones_file)" ]] && cat "$(bunker_visible_zones_file)" || echo "[]"
}

# Link /var/lib/microvms/<zone> -> layer dir when unlocked
link_zone() {
  local name="$1" layer="$2"
  local dest src
  dest="/var/lib/microvms/${name}"
  src="$(layer_dir "$layer")/microvms/${name}"
  mkdir -p "$src"
  mkdir -p /var/lib/microvms
  if [[ -L "$dest" ]]; then
    rm -f "$dest"
  elif [[ -d "$dest" && ! -L "$dest" ]]; then
    echo "WARN: $dest exists as real dir — not replacing (move aside manually)" >&2
    return 0
  fi
  ln -sfn "$src" "$dest"
}

unlink_zone() {
  local name="$1"
  local dest="/var/lib/microvms/${name}"
  if [[ -L "$dest" ]]; then
    rm -f "$dest"
  fi
}

cmd_unlock() {
  local layer="${1:?layer}"
  local pass mode device
  ensure_runtime
  if ! [[ "$layer" =~ ^[0-9]+$ ]]; then
    echo "layer must be integer" >&2
    exit 1
  fi
  if is_unlocked "$layer"; then
    echo "layer $layer already unlocked"
    cmd_sync_visible
    return 0
  fi
  # passphrase from stdin (one line)
  IFS= read -r pass || true
  [[ -n "${pass:-}" ]] || {
    echo "passphrase required on stdin" >&2
    exit 1
  }
  mode="$(bunker_sflc_mode)"
  device="$(bunker_sflc_device)"
  mkdir -p "$(layer_dir "$layer")/microvms"
  if [[ "$mode" == "shufflecake" ]]; then
    if [[ -z "$device" ]]; then
      echo "ERROR: shufflecake mode needs device in shufflecake.json" >&2
      exit 1
    fi
    # Best-effort non-interactive open (CLI may vary by version)
    if printf '%s\n' "$pass" | shufflecake open "$device" 2>/dev/null; then
      true
    elif printf '%s\n' "$pass" | shufflecake open --device "$device" 2>/dev/null; then
      true
    else
      echo "WARN: shufflecake open failed — falling back to stub layer dir (configure device/CLI)" >&2
    fi
  else
    # Stub: derive cookie into RAM-backed run only (not durable key material)
    printf '%s' "$pass" | sha256sum | awk '{print $1}' >"/run/bunker/layer-${layer}.cookie"
    chmod 600 "/run/bunker/layer-${layer}.cookie"
  fi
  # Never store plaintext passphrase
  unset pass
  mark_unlocked "$layer"
  # Link invisible zones on this layer
  python3 - "$(bunker_deniable_json)" "$layer" <<'PY' | while read -r name; do
import json, sys
z = json.load(open(sys.argv[1]))
layer = int(sys.argv[2])
for name, c in z.items():
    if not c.get("invisible"):
        continue
    try:
        if int(c.get("layer") or -1) == layer:
            print(name)
    except (TypeError, ValueError):
        pass
PY
    link_zone "$name" "$layer"
  done
  cmd_sync_visible
  echo "OK: unlocked layer $layer"
}

cmd_lock() {
  local layer="${1:-all}"
  ensure_runtime
  local names
  if [[ "$layer" == "all" ]]; then
    names="$(python3 - "$(bunker_deniable_json)" <<'PY'
import json, sys
z = json.load(open(sys.argv[1]))
for name, c in z.items():
    if c.get("invisible"):
        print(name)
PY
)"
    while read -r name; do
      [[ -z "$name" ]] && continue
      systemctl stop "microvm@${name}.service" 2>/dev/null || true
      unlink_zone "$name"
    done <<<"$names"
    : >"$(bunker_unlocked_layers_file)"
    rm -f /run/bunker/layer-*.cookie
    if command -v shufflecake >/dev/null 2>&1 && [[ -n "$(bunker_sflc_device)" ]]; then
      shufflecake close "$(bunker_sflc_device)" 2>/dev/null || shufflecake close 2>/dev/null || true
    fi
  else
    names="$(python3 - "$(bunker_deniable_json)" "$layer" <<'PY'
import json, sys
z = json.load(open(sys.argv[1]))
layer = int(sys.argv[2])
for name, c in z.items():
    if not c.get("invisible"):
        continue
    try:
        if int(c.get("layer") or -1) == layer:
            print(name)
    except (TypeError, ValueError):
        pass
PY
)"
    while read -r name; do
      [[ -z "$name" ]] && continue
      systemctl stop "microvm@${name}.service" 2>/dev/null || true
      unlink_zone "$name"
    done <<<"$names"
    unmark_unlocked "$layer"
    rm -f "/run/bunker/layer-${layer}.cookie"
  fi
  cmd_sync_visible
  echo "OK: locked $layer"
}

write_desktop() {
  local name="$1" typ="$2"
  local desk="/run/bunker/xdg/applications/qube-invisible-${name}.desktop"
  cat >"$desk" <<EOF
[Desktop Entry]
Type=Application
Name=${name} · ${typ}
Exec=bunker-zone-start ${name}
Icon=applications-system
Categories=X-Qube-AppVM;System
Terminal=false
EOF
}

cmd_sync_visible() {
  ensure_runtime
  local visible_json unlocked
  unlocked="$(tr '\n' ',' <"$(bunker_unlocked_layers_file)" 2>/dev/null || true)"
  visible_json="$(
    UNLOCKED="$unlocked" python3 - "$(bunker_deniable_json)" <<'PY'
import json, os, sys
z = json.load(open(sys.argv[1]))
unlocked = {x for x in os.environ.get("UNLOCKED", "").split(",") if x != ""}
out = []
for name, c in sorted(z.items()):
    if not c.get("invisible"):
        continue
    layer = str(c.get("layer") or "")
    if layer in unlocked:
        out.append(name)
print(json.dumps(out))
PY
  )"
  printf '%s\n' "$visible_json" >"$(bunker_visible_zones_file)"
  rm -f /run/bunker/xdg/applications/qube-invisible-*.desktop
  python3 - "$(bunker_deniable_json)" "$(bunker_visible_zones_file)" <<'PY' | while IFS=$'\t' read -r name typ; do
import json, sys
z = json.load(open(sys.argv[1]))
vis = set(json.load(open(sys.argv[2])))
for name in sorted(vis):
    c = z.get(name, {})
    typ = c.get("kind") or ("disposable" if c.get("disposable") else "appvm")
    print(f"{name}\t{typ}")
PY
    write_desktop "$name" "$typ"
  done
  echo "visible invisible-zones: $visible_json"
}

cmd_path() {
  local name="${1:?zone}"
  python3 - "$(bunker_deniable_json)" "$name" <<'PY'
import json, sys
z = json.load(open(sys.argv[1]))
n = sys.argv[2]
if n not in z or not z[n].get("invisible"):
    raise SystemExit(f"unknown invisible zone: {n}")
print(z[n].get("layer") or "")
PY
}

main() {
  local cmd="${1:-status}"
  shift || true
  case "$cmd" in
    status) cmd_status ;;
    unlock) cmd_unlock "$@" ;;
    lock) cmd_lock "$@" ;;
    sync-visible | sync) cmd_sync_visible ;;
    path) cmd_path "$@" ;;
    -h | --help)
      sed -n '2,10p' "$0" | sed 's/^# //'
      ;;
    *)
      echo "unknown: $cmd" >&2
      exit 1
      ;;
  esac
}

main "$@"
