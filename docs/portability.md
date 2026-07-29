# CPU / arch portability
#
# Same bunker repo on **AMD/Intel (x86_64)**, **ARM (aarch64)**, **RISC-V (riscv64)**.
# Host and guests must share the **same ISA** (KVM). No cross-ISA live zones.

## Matrix

| Chip | `uname -m` | Host flake | Zone packages |
| --- | --- | --- | --- |
| AMD / Intel | `x86_64` | `.#host` | `packages.x86_64-linux.zone-*` |
| ARM64 | `aarch64` / `arm64` | `.#host-aarch64` | `packages.aarch64-linux.zone-*` |
| RISC-V | `riscv64` | `.#host-riscv64` | `packages.riscv64-linux.zone-*` |

`nix run .#zone-personal` always picks **this machine’s** arch.

## First boot

```bash
bunker-first-boot   # prints the right .#host*
sudo nixos-generate-config --show-hardware-config \
  > hosts/bunker/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#host          # or host-aarch64 / host-riscv64
bunker-zone-start net && bunker-zone-start personal
```

## Requirements (every board)

1. NixOS + this flake  
2. **KVM** (or QEMU hypervisor microvm can use)  
3. Real hardware-config (disks/firmware) for *that* board  
4. Patience: RISC-V/ARM may compile more from source; some apps missing in nixpkgs  

## Honest limits

| Claim | Truth |
| --- | --- |
| “Runs on AMD” | Yes — x86_64 path (your current builds) |
| “Runs on ARM” | Wired — native build on the ARM box |
| “Runs on RISC-V” | Wired in flake — **fewer packages**; expect template/app gaps until nixpkgs catches up |
| “One USB stick image for all CPUs” | No — each ISA builds its own closures |
| “Proven live on your metal” | Only after `switch` + zone start on that machine |

## Check

```bash
nix flake show
# expect packages.{x86_64,aarch64,riscv64}-linux.zone-*
```
