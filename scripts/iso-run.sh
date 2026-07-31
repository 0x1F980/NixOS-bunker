#!/usr/bin/env bash
# ISO/HVM zone via QEMU/KVM — works on x86_64, aarch64, riscv64.
# Usage: iso-run.sh <zone>
# Override: BUNKER_QEMU, BUNKER_ISO_ARCH, BUNKER_QEMU_MACHINE, BUNKER_QEMU_CPU, BUNKER_QEMU_BIOS
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
ZONE="${1:?zone}"
ZONES_JSON="$(bunker_zones_json)"
# Optional host-generated qemu hints
if [[ -f /etc/bunker/qemu.env ]]; then
  # shellcheck disable=SC1091
  source /etc/bunker/qemu.env
fi

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

# --- arch: host default, or BUNKER_ISO_ARCH for foreign ISO (TCG) ---
HOST_M=$(uname -m)
case "$HOST_M" in
  amd64) HOST_M=x86_64 ;;
  arm64) HOST_M=aarch64 ;;
esac
ARCH="${BUNKER_ISO_ARCH:-${ARCH:-$HOST_M}}"
case "$ARCH" in
  amd64) ARCH=x86_64 ;;
  arm64) ARCH=aarch64 ;;
esac

NATIVE=0
[[ $ARCH == "$HOST_M" ]] && NATIVE=1
ACCEL="tcg"
[[ $NATIVE -eq 1 ]] && [[ -e /dev/kvm ]] && ACCEL="kvm:tcg"

case "$ARCH" in
  x86_64)
    MACHINE="${BUNKER_QEMU_MACHINE:-q35,accel=${ACCEL}}"
    CPU="${BUNKER_QEMU_CPU:-$([[ $NATIVE -eq 1 ]] && echo host || echo max)}"
    CAND=(qemu-kvm qemu-system-x86_64)
    ;;
  aarch64)
    MACHINE="${BUNKER_QEMU_MACHINE:-virt,accel=${ACCEL},gic-version=max}"
    CPU="${BUNKER_QEMU_CPU:-$([[ $NATIVE -eq 1 ]] && echo host || echo max)}"
    CAND=(qemu-kvm qemu-system-aarch64)
    ;;
  riscv64)
    MACHINE="${BUNKER_QEMU_MACHINE:-virt,accel=${ACCEL}}"
    CPU="${BUNKER_QEMU_CPU:-max}"
    CAND=(qemu-system-riscv64 qemu-kvm)
    ;;
  *)
    echo "unsupported ISO arch: $ARCH (set BUNKER_ISO_ARCH=x86_64|aarch64|riscv64)" >&2
    exit 1
    ;;
esac

QEMU_BIN="${BUNKER_QEMU:-${QEMU_BIN:-}}"
if [[ -z $QEMU_BIN ]]; then
  for c in "${CAND[@]}"; do
    if command -v "$c" >/dev/null; then QEMU_BIN=$(command -v "$c"); break; fi
  done
fi
[[ -n $QEMU_BIN ]] || { echo "no qemu for $ARCH (tried: ${CAND[*]})" >&2; exit 1; }

ARGS=(-name "bunker:${ZONE}[${COLOR}]" -machine "$MACHINE" -cpu "$CPU"
  -m "$MEM" -smp "$VCPU" -device virtio-rng-pci
  -qmp "unix:${QMP},server,nowait"
  -netdev "tap,id=net0,ifname=${TAP},script=no,downscript=no"
  -device "virtio-net-pci,netdev=net0,mac=${MAC}")

# Display: gtk when available, else none (headless / riscv boards)
if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
  ARGS+=(-device qemu-xhci,id=xhci -vga virtio -display gtk,gl=on)
else
  ARGS+=(-nographic)
fi

# UEFI firmware (aarch64 ISO usually needs it; x86 optional)
BIOS="${BUNKER_QEMU_BIOS:-${BIOS:-}}"
if [[ -z ${BIOS:-} ]]; then
  for f in \
    /run/libvirt/nix-ovmf/AAVMF_CODE.fd \
    /run/libvirt/nix-ovmf/OVMF_CODE.fd \
    /usr/share/AAVMF/AAVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd; do
    [[ -f $f ]] && BIOS=$f && break
  done
fi
if [[ -n ${BIOS:-} && -f $BIOS ]]; then
  ARGS+=(-bios "$BIOS")
fi

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
echo "==> ISO $ZONE ($KIND) arch=$ARCH accel=$ACCEL color=$COLOR iso=$ISO"
rm -f "$QMP"
exec "$QEMU_BIN" "${ARGS[@]}"
