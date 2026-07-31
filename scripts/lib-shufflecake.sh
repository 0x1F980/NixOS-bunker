# Shufflecake helpers (sourced by bunker-sflc / panic).
bunker_sflc_conf() {
  [[ -f /etc/bunker/shufflecake.json ]] && echo /etc/bunker/shufflecake.json \
    || echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/shufflecake.json"
}
# Legacy name: public zones path (hidden live only in SFLC layers).
bunker_deniable_json() { bunker_public_zones_json; }
bunker_sflc_get() {
  python3 -c "import json;print(json.load(open('$(bunker_sflc_conf)')).get('$1','') or '')"
}
bunker_sflc_mount_root() { bunker_sflc_get mount_root; }
bunker_sflc_device_cfg() { bunker_sflc_get device; }
bunker_sflc_image_gb() { bunker_sflc_get image_gb; }
bunker_sflc_max_layers() { bunker_sflc_get max_layers; }
bunker_sflc_mode() {
  local m; m=$(bunker_sflc_get mode)
  [[ -n $m ]] || m=shufflecake
  echo "$m"
}
bunker_unlocked_layers_file() { echo /run/bunker/unlocked-layers; }
bunker_visible_zones_file() { echo /run/bunker/visible-zones.json; }
bunker_sflc_state_dir() { echo /run/bunker/sflc; }
bunker_hidden_zones_file() { echo "$(bunker_sflc_mount_root)/layer${1}/hidden-zones.json"; }

# Load dm_sflc (nixpkgs: dm-sflc.ko → modprobe dm_sflc)
bunker_sflc_modprobe() {
  modprobe dm_mod 2>/dev/null || true
  if ! lsmod | grep -q '^dm_sflc'; then
    modprobe dm_sflc 2>/dev/null \
      || modprobe dm-sflc 2>/dev/null \
      || {
        local ko
        ko=$(find /run/current-system/kernel-modules /lib/modules/"$(uname -r)" -name 'dm-sflc.ko*' 2>/dev/null | head -1 || true)
        [[ -n ${ko:-} ]] && insmod "$ko" 2>/dev/null || true
      }
  fi
  lsmod | grep -q '^dm_sflc' || {
    echo "ERROR: dm_sflc kernel module not loaded (Secure Boot? rebuild host with shufflecake)" >&2
    return 1
  }
  command -v shufflecake >/dev/null || {
    echo "ERROR: shufflecake userspace missing" >&2
    return 1
  }
}

# Resolve configured path → block device (losetup if file image)
bunker_sflc_blockdev() {
  local path loop
  path=$(bunker_sflc_device_cfg)
  [[ -n $path ]] || {
    echo "ERROR: shufflecake.json device empty" >&2
    return 1
  }
  if [[ -b $path ]]; then
    echo "$path"
    return 0
  fi
  if [[ -f $path ]]; then
    loop=$(losetup -j "$path" 2>/dev/null | head -1 | cut -d: -f1 || true)
    if [[ -z ${loop:-} ]]; then
      loop=$(losetup -f --show --direct-io=on "$path" 2>/dev/null \
        || losetup -f --show "$path")
    fi
    [[ -b ${loop:-} ]] || {
      echo "ERROR: losetup failed for $path" >&2
      return 1
    }
    echo "$loop" >"$(bunker_sflc_state_dir)/loop"
    echo "$loop"
    return 0
  fi
  echo "ERROR: device/image missing: $path — run: bunker-sflc bootstrap" >&2
  return 1
}

# Mapper for volume index i (0-based): /dev/mapper/sflc_*_$i
bunker_sflc_mapper() {
  local idx=$1 m
  m=$(ls -1 /dev/mapper/sflc_*_"$idx" 2>/dev/null | head -1 || true)
  [[ -n ${m:-} && -b $m ]] || return 1
  echo "$m"
}
