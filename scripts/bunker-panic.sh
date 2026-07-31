#!/usr/bin/env bash
# Panic: verify code → stop lock-zones → wipe wipe-zones → lock sflc → RAM wipe.
# Usage: bunker-panic   (passphrase stdin or BUNKER_PANIC_PASS)
# panic=keep  — leave zone data
# panic=lock  — stop zone VMs (no shred)
# panic=wipe  — shred zone disks
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
# shellcheck source=lib-shufflecake.sh
source "$(dirname "$0")/lib-shufflecake.sh"
CONF=${BUNKER_PANIC_CONF:-/etc/bunker/panic.conf}
expected=$(grep -E '^\s*PANIC_HASH\s*=' "$CONF" 2>/dev/null | tail -1 | sed 's/.*=\s*//' | tr -d ' \r' || true)
[[ -n $expected ]] || { echo "no PANIC_HASH" >&2; exit 1; }
if [[ -n ${BUNKER_PANIC_PASS:-} ]]; then pass=$BUNKER_PANIC_PASS; else IFS= read -r pass || true; fi
got=$(printf '%s' "${pass:-}" | sha256sum | awk '{print $1}')
unset pass
BUNKER_PANIC_PASS=
[[ $got == "$expected" ]] || { echo denied; exit 1; }

# Prefer merged (includes unlocked hidden); fall back to public
DJ=$(bunker_zones_json)
MR=$(bunker_sflc_mount_root)

mapfile -t LOCKZ < <(python3 -c "import json;z=json.load(open('$DJ'));
print('\\n'.join(n for n,c in z.items() if c.get('panic')=='lock'))")
mapfile -t WIPEZ < <(python3 -c "import json;z=json.load(open('$DJ'));
print('\\n'.join(n for n,c in z.items() if c.get('panic') in (True,'wipe')))")
mapfile -t WIPEL < <(python3 -c "import json;z=json.load(open('$DJ'));
print('\\n'.join(str(L) for L in sorted({int(c.get('layer') or 0) for c in z.values() if c.get('panic') in (True,'wipe') and (c.get('invisible') or c.get('slot'))}) if L))")

for z in "${LOCKZ[@]:-}"; do
  [[ -z ${z:-} ]] && continue
  rid=$(bunker_zone_runtime_id "$z" 2>/dev/null || echo "$z")
  systemctl stop "microvm@${rid}.service" 2>/dev/null || true
done

for z in "${WIPEZ[@]:-}"; do
  [[ -z ${z:-} ]] && continue
  rid=$(bunker_zone_runtime_id "$z" 2>/dev/null || echo "$z")
  systemctl stop "microvm@${rid}.service" 2>/dev/null || true
  d=/var/lib/microvms/$rid
  [[ -e $d ]] && {
    command -v srm >/dev/null && srm -rf "$d" || {
      find "$d" -type f -exec shred -u -n 1 {} \; 2>/dev/null
      rm -rf "$d"
    }
  }
done

for L in "${WIPEL[@]:-}"; do
  [[ -z ${L:-} ]] && continue
  ld=$MR/layer$L
  [[ -d $ld ]] && {
    find "$ld" -type f -exec shred -u -n 1 {} \; 2>/dev/null
    rm -rf "$ld"
  }
done

"$(dirname "$0")/bunker-sflc.sh" lock all 2>/dev/null || true
sync
echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || true
command -v sdmem >/dev/null && sdmem -llf 2>/dev/null || true
echo "OK panic. reboot recommended."
