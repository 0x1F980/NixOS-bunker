# CPU / arch portability
#
# Goal: same bunker repo works on **x86_64** and **aarch64** machines.
# Reality: host and guests must share the **same ISA** (KVM). You do not run
# aarch64 zones on an x86 host (or vice versa) except via slow TCG — we do not.

## What the flake does

| Output | x86_64 | aarch64 |
| --- | --- | --- |
| Host | `.#host` | `.#host-aarch64` |
| Zones (nix run) | `.#zone-net` (auto) | `.#zone-net` (auto) |
| Guest configs | `.#net` | `.#net-aarch64` |

`nix run .#zone-personal` picks **this machine’s** `packages.<system>` automatically.

## First boot (any CPU)

```bash
uname -m   # x86_64 or aarch64
sudo nixos-generate-config --show-hardware-config \
  > hosts/bunker/hardware-configuration.nix

# x86_64:
sudo nixos-rebuild switch --flake .#host

# aarch64:
sudo nixos-rebuild switch --flake .#host-aarch64

bunker-zone-start net
bunker-zone-start personal
```

Or: `bunker-first-boot` (detects arch).

## Requirements (same on every board)

1. **Linux + NixOS** (this flake)
2. **KVM** (or equivalent hypervisor usable by QEMU/microvm)
3. Enough RAM for host + on-demand zones
4. Replace the hardware stub with real disks/firmware for *that* board

## Not surprises — honest limits

- **Not one binary for all CPUs.** Each machine builds (or substitutes) **native** closures.
- **Cross-build** (build aarch64 on x86) needs binfmt/qemu-user or a remote aarch64 builder — optional, not required for daily use.
- **Some apps** are arch-limited in nixpkgs (e.g. Obsidian → x86 only today). Templates skip those on ARM; use alternatives in `zones.json` `"apps"`.
- **USB/KVM quirks** are board-specific firmware/driver issues, not bunker locking you to Intel.

## Check

```bash
nix flake show
# expect packages.x86_64-linux.zone-* AND packages.aarch64-linux.zone-*
```
