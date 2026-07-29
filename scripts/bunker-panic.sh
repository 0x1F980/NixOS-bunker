#!/usr/bin/env bash
# Panic: after code check, destroy panic-flagged deniable zone keys/state + best-effort RAM wipe.
# Does NOT wipe public decoy zones or host root LUKS.
# Usage: bunker-panic [--yes]   # passphrase on stdin (one line) unless BUNKER_PANIC_PASS set
set -euo pipefail

# shellcheck source=lib-shufflecake.sh
source "$(dirname "$0")/lib-shufflecake.sh"

CONF="${BUNKER_PANIC_CONF:-/etc/bunker/panic.conf}"
FORCE_YES=0
[[ "${1:-}" == "--yes" ]] && FORCE_YES=1

load_hash() {
  if [[ -f "$CONF" ]]; then
    # shellcheck disable=SC1090
    grep -E '^\s*PANIC_HASH\s*=' "$CONF" | tail -1 | sed 's/.*=\s*//' | tr -d ' \r'
  else
    echo ""
  fi
}

expected="$(load_hash)"
[[ -n "$expected" ]] || {
  echo "ERROR: no PANIC_HASH in $CONF" >&2
  exit 1
}

if [[ -n "${BUNKER_PANIC_PASS:-}" ]]; then
  pass="$BUNKER_PANIC_PASS"
else
  IFS= read -r pass || true
fi
got="$(printf '%s' "${pass:-}" | sha256sum | awk '{print $1}')"
unset pass
BUNKER_PANIC_PASS=""

if [[ "$got" != "$expected" ]]; then
  echo "denied"
  exit 1
fi

if [[ "$FORCE_YES" != "1" ]]; then
  echo "PANIC armed — destroying panic-flagged deniable zone keys/state"
fi

DJ="$(bunker_deniable_json)"
MR="$(bunker_sflc_mount_root)"

# Zones with panic:true
mapfile -t PANIC_ZONES < <(python3 - "$DJ" <<'PY'
import json, sys
z = json.load(open(sys.argv[1]))
for name, c in z.items():
    if c.get("panic") is True:
        print(name)
PY
)

mapfile -t PANIC_LAYERS < <(python3 - "$DJ" <<'PY'
import json, sys
z = json.load(open(sys.argv[1]))
layers = sorted({int(c.get("layer", 0)) for c in z.values() if c.get("panic") is True})
for L in layers:
    print(L)
PY
)

echo "==> stop panic zones: ${PANIC_ZONES[*]:-none}"
for z in "${PANIC_ZONES[@]:-}"; do
  [[ -z "$z" ]] && continue
  systemctl stop "microvm@${z}.service" 2>/dev/null || true
  pkill -f "microvm.*${z}" 2>/dev/null || true
done

echo "==> wipe unlocked panic zone data + key crumbs"
for z in "${PANIC_ZONES[@]:-}"; do
  [[ -z "$z" ]] && continue
  # Follow symlink into layer if present
  dest="/var/lib/microvms/${z}"
  if [[ -e "$dest" ]]; then
    if command -v srm >/dev/null 2>&1; then
      srm -rf "$dest" 2>/dev/null || rm -rf "$dest"
    else
      find "$dest" -type f -exec shred -u -n 1 {} \; 2>/dev/null || true
      rm -rf "$dest"
    fi
  fi
done

for L in "${PANIC_LAYERS[@]:-}"; do
  [[ -z "$L" ]] && continue
  ld="$MR/layer${L}"
  if [[ -d "$ld" ]]; then
    find "$ld" -type f -exec shred -u -n 1 {} \; 2>/dev/null || true
    rm -rf "$ld"
  fi
  rm -f "/run/bunker/layer-${L}.cookie"
  # Durable key crumbs only (never passphrases) — shred if operator stored slot secrets
  if [[ -d /var/lib/bunker/sflc-keys ]]; then
    find /var/lib/bunker/sflc-keys -name "*layer${L}*" -exec shred -u -n 3 {} \; 2>/dev/null || true
    rm -f /var/lib/bunker/sflc-keys/*layer${L}* 2>/dev/null || true
  fi
done

# Lock everything deniable from UI
if [[ -x /etc/bunker/scripts/bunker-sflc.sh ]]; then
  /etc/bunker/scripts/bunker-sflc.sh lock all 2>/dev/null || true
elif [[ -x "$(dirname "$0")/bunker-sflc.sh" ]]; then
  "$(dirname "$0")/bunker-sflc.sh" lock all 2>/dev/null || true
fi

echo "==> best-effort RAM wipe (userspace ≠ coldboot-proof)"
sync
echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || true
if command -v sdmem >/dev/null 2>&1; then
  sdmem -llf 2>/dev/null || sdmem 2>/dev/null || true
elif command -v smem >/dev/null 2>&1; then
  smem 2>/dev/null || true
fi

echo "OK: panic complete for flagged deniable zones. Reboot recommended: systemctl reboot"
echo "HINT: public decoy zones and host LUKS were NOT wiped (deniability)."
exit 0
