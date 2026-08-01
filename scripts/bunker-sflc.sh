#!/usr/bin/env bash
# Invisible zones on real Shufflecake volumes (plausible deniable).
# Hidden zone names live ONLY in layerN/hidden-zones.json — never in public zones.json.
# Usage:
#   bunker-sflc bootstrap [gb]     # create image + init (N passphrases on stdin)
#   bunker-sflc unlock <layer>     # passphrase on stdin → open+mount layer 1..N
#   bunker-sflc lock [layer|all]
#   bunker-sflc status|sync|path <zone>
#   bunker-sflc merge              # rebuild /run/bunker/zones-merged.json
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
# shellcheck source=lib-shufflecake.sh
source "$(dirname "$0")/lib-shufflecake.sh"

ensure() {
  mkdir -p /run/bunker/xdg/applications "$(bunker_sflc_mount_root)" \
    "$(bunker_sflc_state_dir)" /var/lib/bunker
  chmod 700 "$(bunker_sflc_state_dir)" 2>/dev/null || true
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

# Merge public zones + unlocked hidden-zones.json → /run/bunker/zones-merged.json
# Hidden entries are expanded with slot fields (ip/template/…) and marked invisible.
do_merge() {
  ensure
  PUBLIC="$(bunker_public_zones_json)"
  SLOTS="$(bunker_slots_json)"
  MERGED="$(bunker_merged_zones_file)"
  ROOT="$(bunker_sflc_mount_root)"
  UNLOCKED_FILE="$(bunker_unlocked_layers_file)"
  python3 - "$PUBLIC" "$SLOTS" "$MERGED" "$ROOT" "$UNLOCKED_FILE" <<'PY'
import json, os, sys
public_path, slots_path, merged_path, root, unlocked_file = sys.argv[1:6]
public = json.load(open(public_path))
slots = json.load(open(slots_path)) if os.path.isfile(slots_path) else {}
unlocked = set()
if os.path.isfile(unlocked_file):
    unlocked = {ln.strip() for ln in open(unlocked_file) if ln.strip()}
merged = dict(public)
visible = []
for L in sorted(unlocked, key=lambda x: int(x) if x.isdigit() else 0):
    hz = os.path.join(root, f"layer{L}", "hidden-zones.json")
    if not os.path.isfile(hz):
        continue
    hidden = json.load(open(hz))
    for name, hzcfg in hidden.items():
        if name in public:
            print(f"WARN: hidden name '{name}' collides with public zone — skipped", file=sys.stderr)
            continue
        slot_id = hzcfg.get("slot") or ""
        if not slot_id or slot_id not in slots:
            print(f"WARN: hidden '{name}' missing/unknown slot {slot_id!r} — skipped", file=sys.stderr)
            continue
        slot = dict(slots[slot_id])
        # Slot = build-time truth; overlay only ops/UI fields
        entry = dict(slot)
        for k in ("color", "usb", "apps", "panic", "layer"):
            if k in hzcfg and hzcfg[k] is not None:
                entry[k] = hzcfg[k]
        entry["invisible"] = True
        entry["layer"] = int(hzcfg.get("layer") or L)
        entry["slot"] = slot_id
        # internet/template/ip always from slot (guest image)
        merged[name] = entry
        visible.append(name)
with open(merged_path, "w") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")
print(json.dumps(visible))
PY
}

# List friendly names (or slot ids) for hidden zones on unlocked layers
zones_on_layer() {
  LAYER="${1:-}" python3 - "$(bunker_sflc_mount_root)" "$(bunker_unlocked_layers_file)" <<'PY'
import json, os, sys
root, unlocked_file = sys.argv[1:3]
Lfilter = os.environ.get("LAYER") or ""
unlocked = set()
if os.path.isfile(unlocked_file):
    unlocked = {ln.strip() for ln in open(unlocked_file) if ln.strip()}
layers = [Lfilter] if Lfilter else sorted(unlocked, key=lambda x: int(x) if x.isdigit() else 0)
for L in layers:
    if not L:
        continue
    if Lfilter and L != Lfilter:
        continue
    if not Lfilter and L not in unlocked:
        continue
    hz = os.path.join(root, f"layer{L}", "hidden-zones.json")
    if not os.path.isfile(hz):
        continue
    for n, c in json.load(open(hz)).items():
        print(n + "\t" + str(c.get("slot") or n) + "\t" + str(c.get("layer") or L))
PY
}

link_slot() {
  local slot=$1 L=$2 d=/var/lib/microvms/$slot s
  [[ -n $slot ]] || return 1
  s="$(ldir "$L")/microvms/$slot"
  mkdir -p "$s" /var/lib/microvms
  if [[ -L $d ]]; then
    ln -sfn "$s" "$d"
    return 0
  fi
  if [[ -d $d && ! -L $d ]]; then
    # Migrate host-local disk into the deniable layer (first hide after start)
    echo "WARN: migrating $d → $s (was not on Shufflecake layer)" >&2
    mkdir -p "$(dirname "$s")"
    if [[ -e $s ]]; then
      echo "ERROR: both $d and $s exist — move one aside" >&2
      return 1
    fi
    mv "$d" "$s"
  fi
  ln -sfn "$s" "$d"
}

unlink_slot() { [[ -L /var/lib/microvms/$1 ]] && rm -f "/var/lib/microvms/$1"; }

link_all_unlocked() {
  local name slot zl
  while IFS=$'\t' read -r name slot zl; do
    [[ -z ${slot:-} || -z ${zl:-} ]] && continue
    link_slot "$slot" "$zl" || echo "WARN: link_slot $slot L$zl failed" >&2
  done < <(zones_on_layer)
}

sync_vis() {
  ensure
  local vis
  vis="$(do_merge)"
  printf '%s\n' "$vis" >"$(bunker_visible_zones_file)"
  link_all_unlocked
  rm -f /run/bunker/xdg/applications/qube-invisible-*.desktop
  python3 -c "import json;print('\n'.join(json.load(open('$(bunker_visible_zones_file)'))))" 2>/dev/null | while read -r n; do
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
    # Ensure empty hidden manifest exists (no secret names until user creates)
    [[ -f $mp/hidden-zones.json ]] || echo '{}' >"$mp/hidden-zones.json"
    chmod 600 "$mp/hidden-zones.json" 2>/dev/null || true
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

# Interactive: optionally create one hidden zone into layer 1 after init
seed_hidden_prompt() {
  [[ -t 0 && -t 1 ]] || return 0
  local ans name slot usbjson
  read -r -p "Create a deniable hidden zone now? [y/N] " ans || true
  [[ ${ans,,} == y || ${ans,,} == yes ]] || return 0
  read -r -p "Friendly name (secret; only you know it): " name || true
  [[ -n ${name:-} ]] || return 0
  read -r -p "Slot [d1 = radio deniable] (default d1): " slot || true
  slot=${slot:-d1}
  [[ $slot == d1 ]] || { echo "ERROR: only slot d1 (radio) is configured for deniable use" >&2; exit 1; }
  read -r -p "USB vid:pid list (comma, empty=none): " usbjson || true
  # Unlock layer 1 is not done yet at bootstrap — seed file written on first unlock via pending
  mkdir -p "$(bunker_sflc_state_dir)"
  python3 - "$name" "$slot" "${usbjson:-}" "$(bunker_sflc_state_dir)/pending-hidden.json" <<'PY'
import json,sys
name,slot,usb,path=sys.argv[1:5]
usbs=[x.strip() for x in usb.split(",") if x.strip()] if usb else []
json.dump({name:{"slot":slot,"layer":1,"color":"gray","usb":usbs,"panic":"keep","apps":[]}}, open(path,"w"), indent=2)
print(f"pending hidden zone '{name}' → slot {slot} (applied on first unlock of layer 1)")
PY
}

apply_pending_hidden() {
  local pending="$(bunker_sflc_state_dir)/pending-hidden.json" hz
  [[ -f $pending ]] || return 0
  hz="$(ldir 1)/hidden-zones.json"
  [[ -d $(ldir 1) ]] || return 0
  python3 - "$pending" "$hz" <<'PY'
import json,sys,os
pending,hz=sys.argv[1:3]
p=json.load(open(pending))
cur=json.load(open(hz)) if os.path.isfile(hz) else {}
cur.update(p)
json.dump(cur, open(hz,"w"), indent=2)
print("seeded hidden-zones.json:", ", ".join(p))
PY
  shred -u "$pending" 2>/dev/null || rm -f "$pending"
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
  seed_hidden_prompt
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
    apply_pending_hidden
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
  apply_pending_hidden
  local name slot zl
  while IFS=$'\t' read -r name slot zl; do
    [[ -n ${name:-} ]] || continue
    [[ ${zl:-0} -ge 1 && ${zl:-0} -le $L ]] && link_slot "$slot" "$zl" || echo "WARN: link $slot failed" >&2
  done < <(zones_on_layer)
  sync_vis
  echo "OK unlocked layers 1..$L on $dev"
}

do_lock() {
  local L=${1:-all} name slot zl
  ensure
  require_real
  local dev
  dev=$(bunker_sflc_blockdev 2>/dev/null || true)
  while IFS=$'\t' read -r name slot zl; do
    [[ -z ${slot:-} ]] && continue
    systemctl stop "microvm@${slot}.service" 2>/dev/null || true
    unlink_slot "$slot"
  done < <(if [[ $L == all ]]; then zones_on_layer; else zones_on_layer "$L"; fi)
  if [[ $L == all ]]; then
    umount_chain 15
    : >"$(bunker_unlocked_layers_file)"
    [[ -n ${dev:-} ]] && shufflecake close "$dev" 2>/dev/null || true
    if [[ -f $(bunker_sflc_state_dir)/loop ]]; then
      rm -f "$(bunker_sflc_state_dir)/loop" "$(bunker_sflc_state_dir)/open_max_idx"
    fi
    # Drop merged view back to public-only
    rm -f "$(bunker_merged_zones_file)"
    cp "$(bunker_public_zones_json)" "$(bunker_merged_zones_file)" 2>/dev/null || true
  else
    echo "WARN: Shufflecake closes whole cake; locking layer $L → close all, reopen lower if any" >&2
    local lower=$((L - 1))
    umount_chain 15
    [[ -n ${dev:-} ]] && shufflecake close "$dev" 2>/dev/null || true
    : >"$(bunker_unlocked_layers_file)"
    rm -f "$(bunker_merged_zones_file)"
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
  sync|sync-visible|merge) sync_vis ;;
  write-hidden)
    # Replace layerN/hidden-zones.json with JSON object from stdin (root).
    L="${1:?layer}"
    [[ $L =~ ^[0-9]+$ && $L -ge 1 ]] || {
      echo "layer int >= 1" >&2
      exit 1
    }
    ensure
    findmnt -n "$(ldir "$L")" >/dev/null 2>&1 || {
      echo "ERROR: layer $L not mounted — unlock first" >&2
      exit 1
    }
    hz="$(ldir "$L")/hidden-zones.json"
    tmp=$(mktemp)
    cat >"$tmp"
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$tmp" || {
      rm -f "$tmp"
      echo "ERROR: invalid JSON" >&2
      exit 1
    }
    mv "$tmp" "$hz"
    chmod 600 "$hz"
    sync_vis
    echo "OK wrote $hz"
    ;;
  path)
    NAME="${1:?}" python3 -c "
import json, os, sys
z = json.load(open('$(bunker_zones_json)'))
n = os.environ['NAME']
assert n in z and (z[n].get('invisible') or z[n].get('slot')), n
print(z[n].get('layer') or '')
"
    ;;
  -h|--help)
    sed -n '2,10p' "$0" | sed 's/^# //'
    ;;
  *)
    echo "unknown: $cmd" >&2
    exit 1
    ;;
esac
