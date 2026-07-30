#!/usr/bin/env bash
# ISO/HVM zone via QEMU. Usage: iso-run.sh <zone>
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
ZONE="${1:?zone}"
ZONES_JSON="$(bunker_zones_json)"
eval "$(ZONE=$ZONE ZONES_JSON=$ZONES_JSON python3 <<'PY'
import json,os,shlex,sys
z=json.load(open(os.environ["ZONES_JSON"])).get(os.environ["ZONE"]) or sys.exit("unknown")
iso=z.get("iso") or ""
if (z.get("template") or "")!="iso" and not iso: sys.exit("not iso zone")
if not iso: sys.exit("missing iso=")
kind=z.get("kind") or ("disposable" if z.get("disposable") else "appvm")
disp=bool(z.get("disposable")) or kind=="disposable"
for k,v in {
 "ISO":iso,"KIND":kind,"DISPOSABLE":"1" if disp else "0",
 "DISK":z.get("disk") or "","DISK_GB":str(int(z.get("diskGb") or z.get("disk_gb") or 16)),
 "BOOT":(z.get("boot") or "iso").lower(),"MEM":str(int(z.get("mem") or 2048)),
 "VCPU":str(int(z.get("vcpu") or 2)),"IP":z.get("ip") or "",
 "MAC":z.get("mac") or "02:b0:00:00:00:99","COLOR":z.get("color") or "gray",
}.items(): print(f"{k}={shlex.quote(v)}")
PY
)"
[[ -f $ISO ]] || { echo "ISO missing: $ISO" >&2; exit 1; }
DATA="${BUNKER_ISO_DATA:-/var/lib/bunker/iso-zones}/$ZONE"
mkdir -p "$DATA" "$(dirname "${BUNKER_QMP_DIR:-/run/microvm}/${ZONE}.sock")"
QMP="${BUNKER_QMP_DIR:-/run/microvm}/${ZONE}.sock"
TAP="vm-${ZONE}"
[[ -n $DISK ]] || DISK="$DATA/disk.qcow2"
ensure_disk() { [[ -f $DISK ]] || qemu-img create -f qcow2 "$DISK" "${DISK_GB}G"; }
ip link add name br-bunker type bridge 2>/dev/null || true
ip link set br-bunker up 2>/dev/null || true
ip addr replace 10.0.0.254/24 dev br-bunker 2>/dev/null || true
ip link show "$TAP" >/dev/null 2>&1 || ip tuntap add dev "$TAP" mode tap user "${SUDO_USER:-$USER}" 2>/dev/null || true
ip link set "$TAP" master br-bunker 2>/dev/null || true
ip link set "$TAP" up 2>/dev/null || true
QEMU_BIN="${BUNKER_QEMU:-}"
[[ -n $QEMU_BIN ]] || for c in qemu-kvm qemu-system-x86_64; do command -v "$c" >/dev/null && QEMU_BIN=$(command -v "$c") && break; done
[[ -n $QEMU_BIN ]] || { echo "no qemu" >&2; exit 1; }
ARGS=(-name "bunker:${ZONE}[${COLOR}]" -machine type=q35,accel=kvm:tcg -cpu host
  -m "$MEM" -smp "$VCPU" -device virtio-rng-pci -device qemu-xhci,id=xhci
  -qmp "unix:${QMP},server,nowait"
  -netdev "tap,id=net0,ifname=${TAP},script=no,downscript=no"
  -device "virtio-net-pci,netdev=net0,mac=${MAC}" -vga virtio -display gtk,gl=on)
case "$BOOT" in
  disk) ensure_disk; ARGS+=(-drive "file=${DISK},if=virtio,format=qcow2,discard=unmap" -boot order=c);;
  both) ensure_disk; ARGS+=(-drive "file=${DISK},if=virtio,format=qcow2,discard=unmap" -cdrom "$ISO" -boot order=dc);;
  *) ARGS+=(-cdrom "$ISO")
     if [[ $DISPOSABLE == 1 ]]; then
       TMPDISK=$(mktemp "$DATA/overlay.XXXXXX.qcow2"); qemu-img create -f qcow2 "$TMPDISK" 4G
       ARGS+=(-drive "file=${TMPDISK},if=virtio,format=qcow2,discard=unmap" -boot order=d)
       trap 'rm -f "$TMPDISK"' EXIT
     else
       ensure_disk; ARGS+=(-drive "file=${DISK},if=virtio,format=qcow2,discard=unmap" -boot order=dc)
     fi;;
esac
echo "==> ISO $ZONE ($KIND) color=$COLOR iso=$ISO"
rm -f "$QMP"
exec "$QEMU_BIN" "${ARGS[@]}"
