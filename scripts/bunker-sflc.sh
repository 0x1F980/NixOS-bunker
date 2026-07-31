#!/usr/bin/env bash
# Invisible zones on real Shufflecake volumes.
# Usage:
#   bunker-sflc bootstrap [gb]     # create image + init (N passphrases on stdin)
#   bunker-sflc unlock <layer>     # passphrase on stdin → open+mount layer 1..N
#   bunker-sflc lock [layer|all]
#   bunker-sflc status|sync|path <zone>
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
# shellcheck source=lib-shufflecake.sh
source "$(dirname "$0")/lib-shufflecake.sh"

ensure() {
  mkdir -p /run/bunker/xdg/applications "$(bunker_sflc_mount_root)" \
    /var/lib/bunker/sflc-keys "$(bunker_sflc_state_dir)" /var/lib/bunker
  chmod 700 /var/lib/bunker/sflc-keys "$(bunker_sflc_state_dir)" 2>/dev/null || true
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
  elif [[ -d $d && ! -L $d ]]; then
    echo "ERROR: $d is a real directory — move aside before hide" >&2
    return 1
  fi
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

require_real() {
  [[ $(bunker_sflc_mode) == stub ]] && {
    echo "ERROR: mode=stub — set mode=shufflecake in shufflecake.json" >&2
    exit 1
  }
  bunker_sflc_modprobe
}

# Mount volumes 0..maxIdx (inclusive) → layer1..layer(maxIdx+1)
mount_chain() {
  local maxIdx=$1 i mp mapper
  for i in $(seq 0 "$maxIdx"); do
    mapper=$(bunker_sflc_mapper "$i") || {
      echo "ERROR: missing /dev/mapper/sflc_*_$i after open" >&2
      return 1
    }
    mp=$(ldir $((i + 1)))
    mkdir -p "$mp"
    if ! findmnt -n "$mp" >/dev/null 2>&1; then
      if ! blkid "$mapper" >/dev/null 2>&1; then
        echo "==> formatting $mapper (first unlock)"
        mkfs.ext4 -q -F -L "bunker-L$((i + 1))" "$mapper"
      fi
      mount -o nodev,nosuid "$mapper" "$mp"
    fi
    mkdir -p "$mp/microvms"
    mark $((i + 1))
  done
  echo "$maxIdx" >"$(bunker_sflc_state_dir)/open_max_idx"
}

umount_chain() {
  local maxL=${1:-15} i mp
  for i in $(seq "$maxL" -1 1); do
    mp=$(ldir "$i")
    findmnt -n "$mp" >/dev/null 2>&1 && umount "$mp" 2>/dev/null || true
    unmark "$i"
  done
}

bootstrap() {
  require_real
  ensure
  local path gb n passfile
  path=$(bunker_sflc_device_cfg)
  gb=${1:-$(bunker_sflc_image_gb)}
  gb=${gb:-32}
  n=$(bunker_sflc_max_layers)
  n=${n:-3}
  [[ $n =~ ^[0-9]+$ && $n -ge 1 && $n -le 15 ]] || {
    echo "bad max_layers" >&2
    exit 1
  }
  if [[ ! -b $path && ! -f $path ]]; then
    mkdir -p "$(dirname "$path")"
    echo "==> creating sparse image ${path} (${gb}G)"
    truncate -s "${gb}G" "$path"
    chmod 600 "$path"
  fi
  local dev
  dev=$(bunker_sflc_blockdev)
  if ls /dev/mapper/sflc_* >/dev/null 2>&1; then
    echo "ERROR: volumes already open — bunker-sflc lock all first" >&2
    exit 1
  fi
  echo "==> shufflecake init -n $n $dev"
  echo "    provide $n passphrases on stdin (one per line, layer1..layer$n)"
  passfile=$(mktemp)
  trap 'rm -f "$passfile"' EXIT
  if [[ -t 0 ]]; then
    local i p
    : >"$passfile"
    for i in $(seq 1 "$n"); do
      read -r -s -p "layer $i passphrase: " p
      echo
      [[ -n $p ]] || {
        echo "empty passphrase" >&2
        exit 1
      }
      printf '%s\n' "$p" >>"$passfile"
    done
  else
    cat >"$passfile"
    [[ $(wc -l <"$passfile") -ge $n ]] || {
      echo "need $n passphrase lines on stdin" >&2
      exit 1
    }
  fi
  shufflecake -n "$n" init "$dev" <"$passfile"
  shred -u "$passfile" 2>/dev/null || rm -f "$passfile"
  trap - EXIT
  echo "OK bootstrap $dev ($n layers). Unlock: echo pass | bunker-sflc unlock <layer>"
}

do_unlock() {
  local L=$1 pass
  require_real
  ensure
  [[ $L =~ ^[0-9]+$ && $L -ge 1 ]] || {
    echo "layer int >= 1" >&2
    exit 1
  }
  if unlocked "$L" && findmnt -n "$(ldir "$L")" >/dev/null 2>&1; then
    echo "already"
    sync_vis
    exit 0
  fi
  if [[ -t 0 ]]; then
    read -r -s -p "layer $L passphrase: " pass
    echo
  else
    IFS= read -r pass || true
  fi
  [[ -n ${pass:-} ]] || {
    echo "passphrase required" >&2
    exit 1
  }
  local dev
  dev=$(bunker_sflc_blockdev)
  # open (or re-open): close first if already open with fewer layers
  if ls /dev/mapper/sflc_* >/dev/null 2>&1; then
    umount_chain 15
    shufflecake close "$dev" 2>/dev/null || true
  fi
  if ! printf '%s\n' "$pass" | shufflecake open "$dev"; then
    unset pass
    echo "ERROR: shufflecake open failed (wrong passphrase or device not init — bunker-sflc bootstrap)" >&2
    exit 1
  fi
  unset pass
  # Password for volume (L-1) opens volumes 0..L-1
  local maxIdx=$((L - 1))
  bunker_sflc_mapper "$maxIdx" >/dev/null || {
    echo "ERROR: open did not expose volume index $maxIdx — wrong layer password?" >&2
    shufflecake close "$dev" 2>/dev/null || true
    exit 1
  }
  mount_chain "$maxIdx"
  local n zl
  while read -r n; do
    [[ -n $n ]] || continue
    zl=$(python3 -c "import json;print(json.load(open('$(bunker_deniable_json)')).get('$n',{}).get('layer') or 0)")
    [[ ${zl:-0} -ge 1 && ${zl:-0} -le $L ]] && link_z "$n" "$zl"
  done < <(zones_on_layer)
  sync_vis
  echo "OK unlocked layers 1..$L on $dev"
}

do_lock() {
  local L=${1:-all} n
  ensure
  require_real
  local dev
  dev=$(bunker_sflc_blockdev 2>/dev/null || true)
  while read -r n; do
    [[ -z ${n:-} ]] && continue
    systemctl stop "microvm@${n}.service" 2>/dev/null || true
    unlink_z "$n"
  done < <(if [[ $L == all ]]; then zones_on_layer; else zones_on_layer "$L"; fi)
  if [[ $L == all ]]; then
    umount_chain 15
    : >"$(bunker_unlocked_layers_file)"
    [[ -n ${dev:-} ]] && shufflecake close "$dev" 2>/dev/null || true
    # detach loop only if we created it
    if [[ -f $(bunker_sflc_state_dir)/loop ]]; then
      local loop
      loop=$(cat "$(bunker_sflc_state_dir)/loop")
      # keep loop attached for next unlock speed; optional detach:
      # losetup -d "$loop" 2>/dev/null || true
      rm -f "$(bunker_sflc_state_dir)/loop" "$(bunker_sflc_state_dir)/open_max_idx"
    fi
  else
    # Shufflecake only closes whole device — remount lower layers if needed
    echo "WARN: Shufflecake closes whole cake; locking layer $L → close all, reopen lower if any" >&2
    local lower=$((L - 1))
    umount_chain 15
    [[ -n ${dev:-} ]] && shufflecake close "$dev" 2>/dev/null || true
    : >"$(bunker_unlocked_layers_file)"
    if [[ $lower -ge 1 ]]; then
      echo "Re-unlock layers 1..$lower with that layer's passphrase if needed." >&2
    fi
  fi
  sync_vis
  echo "OK locked $L"
}

cmd="${1:-status}"
shift || true
case "$cmd" in
  status)
    ensure
    echo "mode=$(bunker_sflc_mode) device=$(bunker_sflc_device_cfg)"
    echo -n "module: "
    lsmod | grep -q '^dm_sflc' && echo dm_sflc || echo MISSING
    echo -n "mappers: "
    ls /dev/mapper/sflc_* 2>/dev/null | tr '\n' ' ' || echo none
    echo
    echo -n "unlocked: "
    tr '\n' ' ' <"$(bunker_unlocked_layers_file)" 2>/dev/null
    echo
    cat "$(bunker_visible_zones_file)" 2>/dev/null || echo "[]"
    ;;
  bootstrap) bootstrap "${1:-}" ;;
  unlock) do_unlock "${1:?layer}" ;;
  lock) do_lock "${1:-all}" ;;
  sync|sync-visible) sync_vis ;;
  path)
    NAME="${1:?}" python3 - "$(bunker_deniable_json)" <<'PY'
import json,sys,os
z=json.load(open(sys.argv[1])); n=os.environ["NAME"]
assert n in z and z[n].get("invisible"), n
print(z[n].get("layer") or "")
PY
    ;;
  -h|--help)
    sed -n '2,8p' "$0" | sed 's/^# //'
    ;;
  *)
    echo "unknown: $cmd" >&2
    exit 1
    ;;
esac
