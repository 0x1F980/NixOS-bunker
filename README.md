# Hardened, reproducible, compartmentalized NixOS workstation (KVM/microVM).
# Not Qubes — portable across **x86_64 and aarch64** (native ISA + KVM; see [docs/portability.md](docs/portability.md)).

**Repo:** https://github.com/0x1F980/NixOS-bunker

## CPU portability

Ceiling = **all Linux ISAs in nixpkgs** (AMD/Intel, ARM 32/64, RISC-V, POWER, MIPS, LoongArch, s390x, …).  
See [docs/portability.md](docs/portability.md). `bunker-first-boot` picks `.#host` / `.#host-<cpu>` from `uname`.

## Templates + zones (Qubes-like)

| Qubes | Here |
| --- | --- |
| TemplateVM | `templates/*.nix` — edit: `bunker-template-edit desktop` / folder **Templates** |
| AppVM | `zones.json` `kind=appvm` — folder **AppVMs**, title `personal · appvm` |
| DisposableVM | `kind=disposable` — folder **Disposables**, title `browse · disposable` |
| net/usb | folder **Service** — `net · netvm`, `usb · usbvm`, `defaults · service` |

```bash
bunker-zone list
bunker-zone templates
bunker-zone add throwaway --template browser --disposable
bunker-zone set work template=dev internet=i2p
bunker-zone set browse kind=disposable
```

`personal` / `work` / `browse` / `radio` are **examples** in `config/zones.json`.

Infrastructure (not CRUD): **net**, **usb**, **vault**.

## Status (Phase 2)

Phase 2 **config complete**: host/zone eval+build paths, microVM net, Nym/**i2p**/Tor egress,
USB/clipboard, zone CRUD + colors, **x86_64 + aarch64 zone packages**, first-boot docs — pushed to GitHub.

```bash
nix build path:.#nixosConfigurations.host.config.system.build.toplevel
nix build path:.#packages.aarch64-linux.zone-net   # ARM zones wired
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
# x86_64:
sudo nixos-rebuild switch --flake .#host
# aarch64:
# sudo nixos-rebuild switch --flake .#host-aarch64
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
| `bunker-usb-attach <zone> <vid:pid>` | usbVM broker → zone (usbip; 1→many) |
| `bunker-clip send <zone>` | Host clipboard → zone |
| `bunker-clip copy <a> <b>` | Zone → zone (mediated; not left on host clip) |
| `bunker-clip clear` | Wipe staging + host clipboard |
| `bunker-killswitch enable` | Block app-guest→WAN; allow vm-net |
| `bunker-first-boot` | First-boot checklist |
| `bunker-test-isolation [--live]` | Policy (+ optional live) tests |

## Docs

- [docs/portability.md](docs/portability.md) — x86_64 + aarch64
- [docs/usb.md](docs/usb.md) — usbVM broker (1→many)
- [docs/egress.md](docs/egress.md) — netVM / Nym / i2p / Tor
- [docs/nym-bootstrap.md](docs/nym-bootstrap.md)
- [docs/ADMIN-RECOVER.md](docs/ADMIN-RECOVER.md)

## Threat model (honest)

Stronger than a flat desktop, **not** Qubes. Goal: contain compromise to a zone. Closures **build**; runtime proof needs `switch` + `--live`.

**Hackable zones:** `personal`/`work`/`browse`/`radio` are **examples**. Real use = `bunker-zone …` → `config/zones.json` + `templates/`.

| Resource | Model |
| --- | --- |
| **LAN** | Shared br-bunker → netVM |
| **Egress** | Only via netVM (killswitch) |
| **Nym** | One mixnet identity; per-zone SOCKS frontends |
| **USB** | usbVM broker → usbip; one live holder per device |

## License

MIT — see [LICENSE](LICENSE).
