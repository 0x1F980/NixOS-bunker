# Hardened, reproducible, compartmentalized NixOS workstation (KVM/microVM).
# Not Qubes — more portable than Qubes (ARM + lower RAM via on-demand zones).

**Repo:** https://github.com/0x1F980/NixOS-bunker

## Templates + zones (Qubes-like, simple)

| Qubes idea | Here |
| --- | --- |
| TemplateVM | `templates/*.nix` — package sets (`desktop`, `dev`, `browser`, `radio`) |
| AppVM | entries in **`config/zones.nix`** — name, IP, SOCKS, template, disposable? |
| DisposableVM | `disposable = true` + `bunker-wipe <zone>` |

**You edit one file to add your own zones:** [`config/zones.nix`](config/zones.nix)

```nix
# example — add a second disposable browser
throwaway = {
  template = "browser";
  ip = "10.0.0.15";
  mac = "02:b0:00:00:00:15";
  socks = 1085;
  mem = 1536;
  vcpu = 2;
  disposable = true;
};
```

`personal` / `work` / `browse` / `radio` in that file are **examples**, not locked identity. Rename or delete them.

Infrastructure (not in `zones.nix`): **net**, **usb**, **vault**.

## Status (Phase 2)

```bash
nix build path:.#nixosConfigurations.host.config.system.build.toplevel
nix build path:.#zone-net
bunker-test-isolation
```

Replace the **hardware stub**, set **hashed passwords**, then `nixos-rebuild switch --flake .#host`.

## First boot

```bash
git clone git@github.com:0x1F980/NixOS-bunker.git
cd NixOS-bunker

# 1) Edit YOUR zones (optional)
$EDITOR config/zones.nix

# 2) Real disk layout
sudo nixos-generate-config --show-hardware-config > hosts/bunker/hardware-configuration.nix

# 3) Passwords — replace initialPassword with hashedPassword (mkpasswd -m sha-512)

# 4) Switch
sudo nixos-rebuild switch --flake .#host

# 5) Zones
bunker-killswitch enable
bunker-zone-start net
# docs/nym-bootstrap.md
bunker-zone-start personal   # or whatever you named in zones.nix
bunker-wipe browse           # disposable reset

# 6) Checks
bunker-test-isolation
bunker-test-isolation --live
```

## Architecture

| VM | Role |
| --- | --- |
| **net** `10.0.0.1` | Sole egress; Nym/Tor; SOCKS ports from `zones.nix` |
| **usb** `10.0.0.2` | USB broker |
| **vault** | No NIC |
| **app zones** | From `config/zones.nix` on `br-bunker` |
| **host** `10.0.0.254` | Minimal GNOME + orchestration |

## Operator tools

| Command | Purpose |
| --- | --- |
| `bunker-zone-start <zone\|all>` | Start microVM(s) |
| `bunker-wipe <zone>` | Wipe disposable zone data |
| `bunker-usb-attach <vm> <vid:pid>` | One device → one VM (QMP) |
| `bunker-clipboard-send <vm>` | Host → VM clipboard only |
| `bunker-killswitch enable` | Block app-guest→WAN; allow vm-net |
| `bunker-test-isolation [--live]` | Policy (+ optional live) tests |

## Docs

- [docs/nym-bootstrap.md](docs/nym-bootstrap.md)
- [docs/ADMIN-RECOVER.md](docs/ADMIN-RECOVER.md)

## Threat model (honest)

Stronger than a flat desktop, **not** Qubes GUI/dom0 isolation. Closures **build**; runtime proof needs `switch` + `--live` tests on hardware.

## License

MIT — see [LICENSE](LICENSE).
