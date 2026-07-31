# NixOS-bunker

Hardened **KVM**/microVM workstation. Qubes-*like* compartments — **not** Qubes/Xen.

Host clearnet locked. Apps in zones. SOCKS-only via netVM (no guest NAT). Ratatui CRUD. Real Shufflecake. Mediated file copy. Broad hardware: x86_64 · aarch64 · riscv64.

## Documentation

| Doc | For |
| --- | --- |
| **[docs/USER-GUIDE.md](docs/USER-GUIDE.md)** | Daily operator |
| **[docs/DEV-GUIDE.md](docs/DEV-GUIDE.md)** | Tree, LOC, how to change code |
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | Vision + short model |
| [docs/egress.md](docs/egress.md) | SOCKS-only networking |
| [docs/deniable.md](docs/deniable.md) | Skjulte zoner — korrekt brug (PD er ikke magi) |
| [docs/file-copy.md](docs/file-copy.md) | Zone↔zone files |
| [docs/PLAN.md](docs/PLAN.md) | Locked goals |

## Quick start

```bash
bunker
# TUI: h→a  (allow host WAN)
# terminal: sudo nixos-rebuild switch --flake .#host-x86_64-linux
# TUI: h→l  (lock) · b (sflc bootstrap once) · s → net · s → usb · s → personal
```

Or CLI equivalents — see USER-GUIDE. Replace `hardware-configuration.nix` on real machine.