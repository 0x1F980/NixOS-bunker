# Hardened, reproducible, compartmentalized NixOS workstation (KVM/microVM).
# Not Qubes — more portable than Qubes (ARM + lower RAM via on-demand zones).

## Quick start (on a NixOS machine)

```bash
git clone git@github.com:0x1F980/NixOS-bunker.git
cd nixos-bunker

# Optional: import a hardware overlay in hosts/bunker/configuration.nix
#   ../../hardware/generic-x86_64.nix
#   ../../hardware/aarch64-generic.nix
#   ../../hardware/mba52.nix

sudo nixos-generate-config --show-hardware-config > hosts/bunker/hardware-configuration.nix
# Edit passwords: replace initialPassword with hashedPassword

sudo nixos-rebuild switch --flake .#host   # as user `admin`
bunker-zone-start net
bunker-zone-start personal
bunker-test-isolation
```

## Architecture

| VM | Role |
| --- | --- |
| **net** | Sole egress; Nym/Tor/i2pd; DNS/NTP; SOCKS per zone |
| **usb** | USB broker — one device → one VM |
| **personal / work / browse / vault / sdr** | App zones (vault: no NIC) |

Host is minimal GNOME: no daily apps. User `bunker` has **no sudo**. User `admin` is for rebuild/TTY only.

## Clipboard

`bunker-clipboard-send <vm>` — **host → VM only**. Guest → host is refused by policy.

## Update ritual

```bash
bunker-update   # flake update + nixos-rebuild (admin)
```

## Admin lockout recover

1. Boot previous generation from systemd-boot menu.
2. Or boot installer/live → mount root → `nixos-enter` → fix `hashedPassword` / rebuild.
3. Keep a known-good flake generation; do not log into GNOME as `admin`.

## Threat model (honest)

Compartmentalized microVM workstation — stronger than a flat desktop, **not** Qubes GUI/dom0 isolation. Firmware/TEMPEST out of scope.

## License

MIT (or your choice — add LICENSE when publishing).
