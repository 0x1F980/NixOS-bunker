# Hardened, reproducible, compartmentalized NixOS workstation (KVM/microVM).
# Not Qubes — more portable than Qubes (ARM + lower RAM via on-demand zones).

**Repo:** https://github.com/0x1F980/NixOS-bunker

## Status (Phase 2)

Verified on Nix hardware (build, not yet `switch` on your disk layout):

```bash
nix build path:.#nixosConfigurations.host.config.system.build.toplevel
nix build path:.#zone-net
# also: zone-personal / zone-browse / zone-vault (and remaining zones)
bunker-test-isolation   # policy checks; add --live when VMs are up
```

You still must replace the **hardware stub**, set **hashed passwords**, then `nixos-rebuild switch --flake .#host`.

## First boot (on NixOS hardware)

This flake is the **system config**. You still need a NixOS machine (or installer) to apply it.

```bash
git clone git@github.com:0x1F980/NixOS-bunker.git
cd NixOS-bunker

# 1) Real disk layout (replace the stub)
sudo nixos-generate-config --show-hardware-config > hosts/bunker/hardware-configuration.nix
# Prefer LUKS for / and a separate LUKS volume for vault data.

# 2) Optional hardware overlay — uncomment ONE import in hosts/bunker/configuration.nix:
#    ../../hardware/generic-x86_64.nix
#    ../../hardware/aarch64-generic.nix
#    ../../hardware/mba52.nix

# 3) Passwords — replace initialPassword with hashedPassword (mkpasswd -m sha-512)
#    users: bunker (daily, no sudo), admin (TTY / nixos-rebuild only)

# 4) Build & switch (as admin / root)
sudo nixos-rebuild switch --flake .#host

# 5) Network + zones
bunker-killswitch enable
bunker-zone-start net
# Bootstrap Nym inside net VM — see docs/nym-bootstrap.md
bunker-zone-start personal

# 6) Isolation checks
bunker-test-isolation
bunker-test-isolation --live
# Live: from browse VM, clearnet curl without proxy MUST fail;
#       curl -x socks5h://10.0.0.1:1083 https://example.com  after Nym bootstrap
```

## Architecture

| VM | IP | Role |
| --- | --- | --- |
| **net** | 10.0.0.1 | Sole egress; Nym/Tor/i2pd; DNS/NTP; SOCKS 1081–1084; WAN via user-net |
| **usb** | 10.0.0.2 | USB broker |
| **personal** | 10.0.0.11 | Daily apps (template) |
| **work** | 10.0.0.12 | Dev / AI |
| **browse** | 10.0.0.13 | Ephemeral |
| **sdr** | 10.0.0.14 | Radio stack |
| **vault** | — | No NIC; crypto only |
| **host** | 10.0.0.254 on br-bunker | Minimal GNOME + microVM orchestration |

## Operator tools

| Command | Purpose |
| --- | --- |
| `bunker-zone-start <zone\|all>` | Start microVM(s) |
| `bunker-wipe-browse` | Reset browse state |
| `bunker-usb-attach <vm> <vid:pid>` | One device → one VM (QMP) |
| `bunker-usb-detach <vm> <vid:pid>` | Release device |
| `bunker-clipboard-send <vm>` | Host → VM clipboard only |
| `bunker-killswitch enable` | Block app-guest→WAN; allow vm-net |
| `bunker-voice-anon` | Pitch-shift helper |
| `bunker-update` | flake update + rebuild ritual |
| `bunker-test-isolation [--live]` | Policy (+ optional live) smoke tests |

## Docs

- [docs/nym-bootstrap.md](docs/nym-bootstrap.md) — first-time Nym clients on netVM
- [docs/ADMIN-RECOVER.md](docs/ADMIN-RECOVER.md) — admin lockout / rollback

## Threat model (honest)

Compartmentalized microVM workstation — stronger than a flat desktop, **not** Qubes GUI/dom0 isolation. Host/zone closures **build** with Nix; **runtime proof** needs `nixos-rebuild switch` + `bunker-test-isolation --live` on real hardware.

## License

MIT — see [LICENSE](LICENSE).
