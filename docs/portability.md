# CPU / arch portability

## Ceiling (honest)

**Full support = every Linux ISA nixpkgs can target** — not every chip ever fabricated
(no imaginary ISAs, no Windows/Android SoC blobs, no “runs on a toaster”).

Wired in the flake (`bunkerSupportedSystems` / `packages.<system>.zone-*`):

| ISA | Typical chips |
| --- | --- |
| `x86_64-linux` | AMD, Intel 64-bit |
| `i686-linux` | 32-bit x86 |
| `aarch64-linux` | ARM64 (Apple Silicon/Linux, RPi4/5, Ampere, …) |
| `armv7l-linux` / `armv6l-linux` | 32-bit ARM |
| `riscv64-linux` / `riscv32-linux` | RISC-V |
| `powerpc64le-linux` / `powerpc64-linux` / `powerpc-linux` | POWER / PPC |
| `mipsel-linux` / `mips64el-linux` | MIPS |
| `loongarch64-linux` | LoongArch |
| `s390x-linux` | IBM Z |
| \+ any other `*-linux` in `lib.systems.flakeExposed` | as nixpkgs adds them |

Same **module config** everywhere. Binaries are native per ISA. Host attr:

```text
x86_64  →  .#host
other   →  .#host-<cpu>   e.g. host-aarch64, host-riscv64, host-loongarch64
```

`bunker-first-boot` / `bunker-update` map `uname -m` automatically.

## Still required on every board

1. Linux + KVM (or usable QEMU for microvm)  
2. `nixos-generate-config` → real disks/firmware  
3. Some apps missing on exotic ISAs (templates soft-skip)

## Not in scope

- macOS/Windows as host (this is NixOS)  
- Cross-ISA KVM (aarch64 zones on AMD without TCG — not supported)  
- Guaranteeing every GUI app builds on MIPS/RISC-V day one
