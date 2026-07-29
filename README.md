# Hardened, reproducible, compartmentalized NixOS workstation (KVM/microVM).
# Not Qubes — more portable than Qubes (ARM + lower RAM via on-demand zones).

**Repo:** https://github.com/0x1F980/NixOS-bunker

## Templates + zones (Qubes-like)

| Qubes idea | Here |
| --- | --- |
| TemplateVM | `templates/*.nix` (`desktop`, `dev`, `browser`, `radio`) |
| AppVM / CRUD | **`config/zones.json`** via `bunker-zone` |
| DisposableVM | `"disposable": true` + `bunker-wipe <zone>` |
| Label colors | `"color": "red\|orange\|yellow\|green\|blue\|purple\|…"` |
| Per-VM apps | `"apps": ["htop", "vim"]` (nixpkgs names) |
| Net policy | `"internet": "nym" \| "i2p" \| "tor" \| "none"` |
| USB defaults | `"usb": ["0bda:2838"]` auto-attach on start |

Egress: **Nym** (one identity) / **i2p** alternative / **Tor** — [docs/egress.md](docs/egress.md).

### Zone CRUD

```bash
bunker-zone list
bunker-zone colors
bunker-zone add throwaway --template browser --color red --disposable
bunker-zone set throwaway internet=i2p
bunker-zone apps throwaway add htop
bunker-zone usb radio add 0bda:2838
bunker-zone rm throwaway
# then:
sudo nixos-rebuild switch --flake .#host
bunker-zone-start throwaway
bunker-term throwaway          # colored terminal into the zone
```

`personal` / `work` / `browse` / `radio` are **examples** in `config/zones.json`.

Infrastructure (not CRUD): **net**, **usb**, **vault**.

## Status (Phase 2)

Phase 2 **config complete**: host/zone eval+build paths, microVM net, Nym/**i2p**/Tor egress,
USB/clipboard, zone CRUD + colors, first-boot docs — pushed to GitHub.

```bash
nix build path:.#nixosConfigurations.host.config.system.build.toplevel
nix build path:.#zone-net
bunker-test-isolation
bunker-zone list
```

Still on **you** for a live machine: replace hardware stub, hashed passwords,
`nixos-rebuild switch`, `bunker-zone-start net`, then `bunker-test-isolation --live`.

## First boot

```bash
git clone git@github.com:0x1F980/NixOS-bunker.git
cd NixOS-bunker
bunker-first-boot
# edit zones: bunker-zone add|set|…   OR  nano config/zones.json
sudo nixos-generate-config --show-hardware-config > hosts/bunker/hardware-configuration.nix
# hashed passwords in modules/host-minimal.nix
sudo nixos-rebuild switch --flake .#host
bunker-killswitch enable
bunker-zone-start net
bunker-zone-start personal
bunker-term personal
bunker-test-isolation --live
```

## Operator tools

| Command | Purpose |
| --- | --- |
| `bunker-zone …` | CRUD zones / apps / usb / colors |
| `bunker-zone-start <zone\|all>` | Start microVM(s) (+ USB defaults) |
| `bunker-term <zone>` | Colored SSH shell into zone |
| `bunker-wipe <zone>` | Wipe disposable zone data |
| `bunker-usb-attach <vm> <vid:pid>` | One device → one VM (QMP) |
| `bunker-clip send <zone>` | Host clipboard → zone |
| `bunker-clip copy <a> <b>` | Zone → zone (mediated; not left on host clip) |
| `bunker-clip clear` | Wipe staging + host clipboard |
| `bunker-killswitch enable` | Block app-guest→WAN; allow vm-net |
| `bunker-first-boot` | First-boot checklist |
| `bunker-test-isolation [--live]` | Policy (+ optional live) tests |

## Docs

- [docs/nym-bootstrap.md](docs/nym-bootstrap.md)
- [docs/ADMIN-RECOVER.md](docs/ADMIN-RECOVER.md)

## Threat model (honest)

Stronger than a flat desktop, **not** Qubes GUI/dom0 isolation. Closures **build**; runtime proof needs `switch` + `--live` on hardware.

**Demo vs hackable:** `personal` / `work` / `browse` / `radio` / `vault` in the repo are **example** zones. Real use = edit `config/zones.json` (`bunker-zone …`) and/or templates.

**Shared vs exclusive**

| Resource | Model |
| --- | --- |
| **LAN (br-bunker)** | Shared — all app zones can talk to netVM |
| **Clearnet egress** | Only via netVM (killswitch); not per-zone WAN NICs |
| **Nym** | **One** mixnet identity; zone SOCKS ports are frontends to it |
| **USB** | Many zones may *list* a device; **live** attach = **one VM at a time** (hardware). Re-attach **moves** the device. |

## Threat model (honest)

Stronger than a flat desktop, **not** Qubes GUI/dom0 isolation. Goal: **contain** compromise to a zone — not TEMPEST/Qubes-level. Reproducible Nix config; on-demand microVMs keep RAM/CPU modest. Closures **build**; runtime proof needs `switch` + `--live` on hardware.

## License

MIT — see [LICENSE](LICENSE).
