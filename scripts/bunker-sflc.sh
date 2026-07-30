#!/usr/bin/env bash
# Invisible zones: unlock/lock Shufflecake layers + GNOME launchers.
# Usage: bunker-sflc status|unlock <n>|lock [n|all]|unlock-zone <name>|lock-zone <name>|sync|path <zone>
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
# shellcheck source=lib-shufflecake.sh
source "$(dirname "$0")/lib-shufflecake.sh"

ensure() {
  mkdir -p /run/bunker/xdg/applications "$(bunker_sflc_mount_root)" /var/lib/bunker/sflc-keys
  chmod 700 /var/lib/bunker/sflc-keys 2>/dev/null || true
  touch "$(bunker_unlocked_layers_file)" 2>/dev/null || true
}
ldir() { echo "$(bunker_sflc_mount_root)/layer$1"; }
unlocked() { grep -qx "$1" "$(bunker_unlocked_layers_file)" 2>/dev/null; }
mark() { ensure; unlocked "$1" || echo "$1" >>"$(bunker_unlocked_layers_file)"; }
unmark() {
  local f; f="$(bunker_unlocked_layers_file)"
  [[ -f $f ]] || return 0
  grep -vx "$1" "$f" >"$f.tmp" 2>/dev/null || true; mv "$f.tmp" "$f"
}

zones_on_layer() {
  # all invisible, or those on layer $1
  LAYER="${1:-}" python3 - "$(bunker_deniable_json)" <<'PY'
import json,os,sys
z=json.load(open(sys.argv[1])); L=os.environ.get("LAYER") or ""
for n,c in z.items():
  if not c.get("invisible"): continue
  if L and str(c.get("layer") or "")!=L: continue
  print(n)
PY
}

link_z() {
  local n=$1 L=$2 d=/var/lib/microvms/$n s; s="$(ldir "$L")/microvms/$n"
  mkdir -p "$s" /var/lib/microvms
  if [[ -L $d ]]; then rm -f "$d"
  elif [[ -d $d ]]; then echo "WARN: $d real dir" >&2; return 0; fi
  ln -sfn "$s" "$d"
}
unlink_z() { [[ -L /var/lib/microvms/$1 ]] && rm -f "/var/lib/microvms/$1"; }

sync_vis() {
  ensure
  local unlocked vis
  unlocked="$(tr '\n' ',' <"$(bunker_unlocked_layers_file)" 2>/dev/null || true)"
  vis="$(UNLOCKED=$unlocked python3 - "$(bunker_deniable_json)" <<'PY'
import json,os,sys
z=json.load(open(sys.argv[1]))
u={x for x in os.environ.get("UNLOCKED","").split(",") if x}
print(json.dumps([n for n,c in sorted(z.items()) if c.get("invisible") and str(c.get("layer") or "") in u]))
PY
)"
  printf '%s\n' "$vis" >"$(bunker_visible_zones_file)"
  rm -f /run/bunker/xdg/applications/qube-invisible-*.desktop
  python3 -c "import json;print('\n'.join(json.load(open('$(bunker_visible_zones_file)'))))" | while read -r n; do
    [[ -z $n ]] && continue
    cat >"/run/bunker/xdg/applications/qube-invisible-${n}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${n}
Exec=bunker-zone-start ${n}
Icon=applications-system
Categories=X-Qube-AppVM;System
Terminal=false
EOF
  done
  echo "visible: $vis"
}


zone_layer() {
  NAME="${1:?}" python3 - "$(bunker_deniable_json)" <<'PY'
import json,sys,os
z=json.load(open(sys.argv[1])); n=os.environ["NAME"]
c=z.get(n) or {}
assert c.get("invisible"), n
print(c.get("layer") or "")
PY
}

zone_hide_hash() {
  NAME="${1:?}" python3 - "$(bunker_deniable_json)" <<'PY'
import json,sys,os
z=json.load(open(sys.argv[1])); n=os.environ["NAME"]
print((z.get(n) or {}).get("hideHash") or "")
PY
}

verify_zone_pass() {
  # $1 zone, passphrase on stdin — checks hideHash if set
  local n=$1 want got
  want="$(zone_hide_hash "$n")"
  IFS= read -r pass || true
  [[ -n ${pass:-} ]] || { echo "passphrase on stdin" >&2; return 1; }
  if [[ -n $want ]]; then
    got="$(printf '%s' "$pass" | sha256sum | awk '{print $1}')"
    [[ $got == "$want" ]] || { echo "denied: wrong passphrase for zone $n" >&2; unset pass; return 1; }
  fi
  printf '%s\n' "$pass"
  unset pass
}

cmd="${1:-status}"; shift || true
case "$cmd" in
  status)
    ensure
    echo "mode=$(bunker_sflc_mode) device=$(bunker_sflc_device)"
    echo -n "unlocked: "; tr '\n' ' ' <"$(bunker_unlocked_layers_file)" 2>/dev/null; echo
    cat "$(bunker_visible_zones_file)" 2>/dev/null || echo "[]"
    ;;
  unlock)
    L="${1:?layer}"; ensure
    [[ $L =~ ^[0-9]+$ ]] || { echo "layer int"; exit 1; }
    if unlocked "$L"; then echo "already"; sync_vis; exit 0; fi
    IFS= read -r pass || true
    [[ -n ${pass:-} ]] || { echo "passphrase on stdin"; exit 1; }
    mkdir -p "$(ldir "$L")/microvms"
    if [[ $(bunker_sflc_mode) == shufflecake ]]; then
      d=$(bunker_sflc_device); [[ -n $d ]] || { echo "need device"; exit 1; }
      printf '%s\n' "$pass" | shufflecake open "$d" 2>/dev/null \
        || printf '%s\n' "$pass" | shufflecake open --device "$d" 2>/dev/null \
        || echo "WARN: shufflecake open failed — stub dir" >&2
    else
      printf '%s' "$pass" | sha256sum | awk '{print $1}' >"/run/bunker/layer-${L}.cookie"
      chmod 600 "/run/bunker/layer-${L}.cookie"
    fi
    unset pass; mark "$L"
    while read -r n; do [[ -n $n ]] && link_z "$n" "$L"; done < <(zones_on_layer "$L")
    sync_vis; echo "OK unlocked $L"
    ;;
  lock)
    L="${1:-all}"; ensure
    while read -r n; do
      [[ -z $n ]] && continue
      systemctl stop "microvm@${n}.service" 2>/dev/null || true
      unlink_z "$n"
    done < <(if [[ $L == all ]]; then zones_on_layer; else zones_on_layer "$L"; fi)
    if [[ $L == all ]]; then
      : >"$(bunker_unlocked_layers_file)"; rm -f /run/bunker/layer-*.cookie
      command -v shufflecake >/dev/null && [[ -n $(bunker_sflc_device) ]] \
        && { shufflecake close "$(bunker_sflc_device)" 2>/dev/null || true; }
    else
      unmark "$L"; rm -f "/run/bunker/layer-${L}.cookie"
    fi
    sync_vis; echo "OK locked $L"
    ;;
  sync|sync-visible) sync_vis ;;
  unlock-zone)
    # Unlock ONE invisible zone via its unique layer (+ optional hideHash).
    # Other hidden zones on other layers stay locked.
    NAME="${1:?zone}"; ensure
    L="$(zone_layer "$NAME")"
    [[ -n $L && $L =~ ^[0-9]+$ ]] || { echo "zone $NAME has no layer" >&2; exit 1; }
    pass="$(verify_zone_pass "$NAME")" || exit 1
    if unlocked "$L"; then echo "already"; sync_vis; exit 0; fi
    mkdir -p "$(ldir "$L")/microvms"
    if [[ $(bunker_sflc_mode) == shufflecake ]]; then
      d=$(bunker_sflc_device); [[ -n $d ]] || { echo "need device"; exit 1; }
      printf '%s\n' "$pass" | shufflecake open "$d" 2>/dev/null \
        || printf '%s\n' "$pass" | shufflecake open --device "$d" 2>/dev/null \
        || echo "WARN: shufflecake open failed — stub dir" >&2
    else
      printf '%s' "$pass" | sha256sum | awk '{print $1}' >"/run/bunker/layer-${L}.cookie"
      chmod 600 "/run/bunker/layer-${L}.cookie"
    fi
    unset pass; mark "$L"
    link_z "$NAME" "$L"
    sync_vis; echo "OK unlocked zone $NAME (layer $L)"
    ;;
  lock-zone)
    NAME="${1:?zone}"; ensure
    L="$(zone_layer "$NAME")"
    [[ -n $L && $L =~ ^[0-9]+$ ]] || { echo "zone $NAME has no layer" >&2; exit 1; }
    systemctl stop "microvm@${NAME}.service" 2>/dev/null || true
    unlink_z "$NAME"
    # If no other zone still needs this layer, lock the layer.
    others="$(zones_on_layer "$L" | grep -vx "$NAME" || true)"
    if [[ -z $others ]]; then
      unmark "$L"; rm -f "/run/bunker/layer-${L}.cookie"
    fi
    sync_vis; echo "OK locked zone $NAME"
    ;;
  path)
    NAME="${1:?}"
    zone_layer "$NAME"
    ;;
  -h|--help) sed -n '2,3p' "$0" | sed 's/^# //';;
  *) echo "unknown: $cmd" >&2; exit 1;;
esac
