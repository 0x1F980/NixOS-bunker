#!/usr/bin/env bash
# Run an ISO / HVM zone with QEMU (Tails, other live ISOs, installed guests).
# Not a NixOS microVM — same zones.json fields: kind, color, internet, usb, mem, …
#
# Usage: iso-run.sh <zone>
# Requires: zone.template == "iso" and zone.iso = absolute path to .iso/.img
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

ZONE="${1:-}"
[[ -n "$ZONE" ]] || {
  echo "Usage: $0 <zone>" >&2
  exit 1
}

ZONES_JSON="$(bunker_zones_json)"
[[ -f "$ZONES_JSON" ]] || {
  echo "ERROR: zones.json not found" >&2
  exit 1
}

eval "$(
  ZONE="$ZONE" ZONES_JSON="$ZONES_JSON" python3 <<'PY'
import json, os, shlex, sys
z = json.load(open(os.environ["ZONES_JSON"])).get(os.environ["ZONE"])
if not z:
    sys.exit("unknown zone")
tmpl = z.get("template") or ""
iso = z.get("iso") or ""
if tmpl != "iso" and not iso:
    sys.exit("not an iso zone (set template=iso and iso=/path/to.iso)")
if not iso:
    sys.exit("iso zone missing iso=/path/to.file")
kind = z.get("kind") or ("disposable" if z.get("disposable") else "appvm")
disp = bool(z.get("disposable")) or kind == "disposable"
disk = z.get("disk") or ""
disk_gb = int(z.get("diskGb") or z.get("disk_gb") or 16)
boot = (z.get("boot") or "iso").lower()  # iso | disk | both
display = (z.get("display") or "gtk").lower()
mem = int(z.get("mem") or 2048)
vcpu = int(z.get("vcpu") or 2)
ip = z.get("ip") or ""
mac = z.get("mac") or "02:b0:00:00:00:99"
color = z.get("color") or "gray"
internet = z.get("internet") or "nym"
socks = z.get("socks")
socks_s = "" if socks is None else str(socks)
for k, v in {
    "ISO": iso,
    "KIND": kind,
    "DISPOSABLE": "1" if disp else "0",
    "DISK": disk,
    "DISK_GB": str(disk_gb),
    "BOOT": boot,
    "DISPLAY": display,
    "MEM": str(mem),
    "VCPU": str(vcpu),
    "IP": ip,
    "MAC": mac,
    "COLOR": color,
    "INTERNET": internet,
    "SOCKS": socks_s,
}.items():
    print(f"{k}={shlex.quote(v)}")
PY
)"

if [[ ! -f "$ISO" ]]; then
  echo "ERROR: ISO not found: $ISO" >&2
  echo "  Place the file and: bunker-zone set $ZONE iso=/absolute/path.iso" >&2
  exit 1
fi

DATA_ROOT="${BUNKER_ISO_DATA:-/var/lib/bunker/iso-zones}"
DATA="$DATA_ROOT/$ZONE"
mkdir -p "$DATA"
QMP="${BUNKER_QMP_DIR:-/run/microvm}/${ZONE}.sock"
mkdir -p "$(dirname "$QMP")"
TAP="vm-${ZONE}"

# Persistent disk for appvm/template; disposable uses snapshot or temp overlay
if [[ -z "$DISK" ]]; then
  DISK="$DATA/disk.qcow2"
fi

ensure_disk() {
  if [[ -f "$DISK" ]]; then
    return 0
  fi
  echo "==> creating ${DISK_GB}G disk $DISK"
  mkdir -p "$(dirname "$DISK")"
  qemu-img create -f qcow2 "$DISK" "${DISK_GB}G"
}

ensure_bridge() {
  if command -v ip >/dev/null 2>&1; then
    ip link add name br-bunker type bridge 2>/dev/null || true
    ip link set br-bunker up 2>/dev/null || true
    ip addr replace 10.0.0.254/24 dev br-bunker 2>/dev/null || true
  fi
}

setup_tap() {
  ensure_bridge
  if ! ip link show "$TAP" >/dev/null 2>&1; then
    ip tuntap add dev "$TAP" mode tap user "${SUDO_USER:-$USER}" 2>/dev/null \
      || ip tuntap add dev "$TAP" mode tap || true
  fi
  ip link set "$TAP" master br-bunker 2>/dev/null || true
  ip link set "$TAP" up 2>/dev/null || true
}

cleanup_tap() {
  # Leave tap for reuse; optional down
  true
}

QEMU_BIN="${BUNKER_QEMU:-}"
if [[ -z "$QEMU_BIN" ]]; then
  for c in qemu-kvm qemu-system-x86_64; do
    if command -v "$c" >/dev/null 2>&1; then
      QEMU_BIN="$(command -v "$c")"
      break
    fi
  done
fi
[[ -n "$QEMU_BIN" ]] || {
  echo "ERROR: qemu-kvm / qemu-system-x86_64 not found" >&2
  exit 1
}

setup_tap

ARGS=(
  -name "bunker:${ZONE}[${COLOR}]"
  -machine type=q35,accel=kvm:tcg
  -cpu host
  -m "$MEM"
  -smp "$VCPU"
  -device virtio-rng-pci
  -device qemu-xhci,id=xhci
  -qmp "unix:${QMP},server,nowait"
  -netdev "tap,id=net0,ifname=${TAP},script=no,downscript=no"
  -device "virtio-net-pci,netdev=net0,mac=${MAC}"
  -vga virtio
)

case "$DISPLAY" in
  none|nographic)
    ARGS+=(-display none -serial mon:stdio)
    ;;
  spice)
    SPICE_PORT="${BUNKER_SPICE_PORT:-$((5900 + (${IP##*.})))}"
    ARGS+=(-display "spice-app" -spice "port=${SPICE_PORT},disable-ticketing=on")
    echo "SPICE port $SPICE_PORT"
    ;;
  *)
    # gtk — interactive desktop ISOs (Tails, …)
    ARGS+=(-display gtk,gl=on)
    ;;
esac

# Boot media
case "$BOOT" in
  disk)
    ensure_disk
    ARGS+=(-drive "file=${DISK},if=virtio,format=qcow2,discard=unmap")
    ARGS+=(-boot order=c)
    ;;
  both)
    ensure_disk
    ARGS+=(-drive "file=${DISK},if=virtio,format=qcow2,discard=unmap")
    ARGS+=(-cdrom "$ISO")
    ARGS+=(-boot order=dc)
    ;;
  iso|*)
    ARGS+=(-cdrom "$ISO")
    if [[ "$DISPOSABLE" == "1" ]]; then
      # Ephemeral writable disk; removed when QEMU exits
      TMPDISK="$(mktemp "$DATA/overlay.XXXXXX.qcow2")"
      qemu-img create -f qcow2 "$TMPDISK" 4G
      ARGS+=(-drive "file=${TMPDISK},if=virtio,format=qcow2,discard=unmap")
      ARGS+=(-boot order=d)
      trap 'rm -f "$TMPDISK"; cleanup_tap' EXIT
    else
      ensure_disk
      ARGS+=(-drive "file=${DISK},if=virtio,format=qcow2,discard=unmap")
      ARGS+=(-boot order=dc)
    fi
    ;;
esac

echo "==> ISO zone $ZONE ($KIND) color=$COLOR internet=$INTERNET"
echo "    iso=$ISO"
echo "    mac=$MAC ip=$IP (guest must use this on eth0; gw 10.0.0.1)"
if [[ -n "$SOCKS" ]]; then
  echo "    SOCKS via netVM: 10.0.0.1:${SOCKS} (nym) / +1000 i2p / +2000 tor"
fi
echo "    qmp=$QMP  tap=$TAP"
echo "    hint: Tails often wants internet=none (own Tor). USB: bunker-usb-attach $ZONE vid:pid"

# Already running?
if [[ -S "$QMP" ]] && socat -u OPEN:/dev/null UNIX-CONNECT:"$QMP" 2>/dev/null; then
  echo "WARN: QMP $QMP already accepting — zone may already be running" >&2
fi

rm -f "$QMP"
exec "$QEMU_BIN" "${ARGS[@]}"
