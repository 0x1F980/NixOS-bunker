# Hardened, reproducible, compartmentalized NixOS workstation (KVM/microVM).
# Not Qubes — portable across **x86_64 and aarch64** (native ISA + KVM; see [docs/portability.md](docs/portability.md)).

**Repo:** https://github.com/0x1F980/NixOS-bunker

## Layout

| Path | Role |
| --- | --- |
| `config/zones.json` | **Source of truth** for AppVMs / Disposables (CRUD: `bunker-zone`) |
| `templates/*.nix` | TemplateVM package sets |
| `modules/guests/` | netVM, usbVM, vault, `mk-app-zone` |
| `modules/` | Host UI, clipboard, killswitch wiring, registry |
| `scripts/` | Operator tools (`lib-common.sh`, `lib-arch.sh`) |
| `tools/bunker-broker-tui/` | Ratatui net/usb defaults (`defaults · service`) |
| `tools/bunker-zones-tui/` | Ratatui AppVM/Disposable CRUD (`zones · service`) |
| `tools/bunker-deniable-tui/` | Ratatui hidden whole-VMs / Shufflecake (`deniable · service`) |
| `tools/bunker-voice-tui/` | Ratatui voiceVM mic anonymizer (`voice · service`) |
| `config/deniable-zones.json` | Deniable whole-VM registry |
| `docs/` | Topic docs + `MANUAL.txt` (also `man bunker`) |
| `man/bunker.1` | Operator manpage |
| `hardware/mba52.nix` | Optional board overlay — **not** imported by default |

## Templates + zones (Qubes-like)

| Qubes | Here |
| --- | --- |
| TemplateVM | `templates/*.nix` — edit: `bunker-template-edit desktop` / folder **Templates** |
| AppVM | `zones.json` `kind=appvm` — folder **AppVMs**, title `personal · appvm` |
| DisposableVM | `kind=disposable` — folder **Disposables**, title `browse · disposable` |
| net/usb | folder **Service** — `net · netvm`, `usb · usbvm`, `defaults · service` |

```bash
bunker-zones          # ratatui CRUD (preferred UX)
bunker-zone list
bunker-zone templates
bunker-zone add throwaway --template browser --disposable
bunker-zone set work template=dev internet=i2p
bunker-zone set browse kind=disposable
```

Prefer **zones · service** / `bunker-zones` / `bunker-zone` over editing Nix modules for per-zone CRUD.
Hand-editing `config/zones.json` is fine (same source of truth); then `nixos-rebuild switch`.
Do **not** hand-edit `modules/` just to add/remove a zone.

`personal` / `work` / `browse` / `radio` are **examples** in `config/zones.json` (zone name is `radio`, not `sdr`).
Infrastructure (not CRUD): **net**, **usb**, **vault**.

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

`bunker-first-boot` picks `.#host` / `.#host-<cpu>` from `uname` ([docs/portability.md](docs/portability.md)).

## Operator tools

| Command | Purpose |
| --- | --- |
| `bunker-zone …` | CRUD zones / apps / usb / colors (CLI) |
| `bunker-zones` / **zones · service** | Ratatui CRUD for AppVMs / Disposables |
| `bunker-deniable` / **deniable · service** | Hide/show **whole** VMs (Shufflecake layers) |
| `bunker-panic-ui` / **panic · service** | ☢ Wipe panic-flagged deniable keys + RAM wipe |
| `bunker-broker` / **defaults · service** | Ratatui net/usb broker defaults |
| `bunker-voice` / **voice · service** | Ratatui mic anonymizer 1→many (Chimera/anon) |
| `bunker-zone-start <zone\|all>` | Start microVM(s) (+ USB defaults) |
| `bunker-term <zone>` | Colored SSH shell into zone |
| `bunker-wipe <zone>` | Wipe disposable zone data |
| `bunker-usb-attach <zone> <vid:pid>` | usbVM broker → zone (usbip; 1→many) |
| `bunker-clip send <zone>` | Host → zone (host clip **kept**; zone clip clears after TTL) |
| `bunker-clip copy <a> <b>` | Zone → zone (mediated; not on host clip) |
| `bunker-clip clear` | Wipe staging + host clipboard **now** |
| `bunker-killswitch enable` | Block app-guest→WAN; allow vm-net |
| `bunker-first-boot` | First-boot checklist |
| `bunker-test-isolation [--live]` | Policy (+ optional live) tests |
| `man bunker` / `bunker-help` | Operator manpage (also **help · service**) |

Clipboard TTL (default **30s**): edit `/etc/bunker/clipboard.conf` or `BUNKER_CLIP_TTL=60`.

**Host emergency (VMs down):** Disks, GParted, Files, Disk Usage, Text Editor, Logs + CLI `cryptsetup` / `ddrescue` / `testdisk` / `rsync` / `borg`. Destructive work → `admin` + sudo.

## Docs

- **`man bunker`** or [docs/MANUAL.txt](docs/MANUAL.txt) (`/etc/bunker/MANUAL`)
- [docs/deniable.md](docs/deniable.md) — hidden whole-VMs + panic
- [docs/voice.md](docs/voice.md) — voiceVM mic anonymizer (Chimera)
- [docs/portability.md](docs/portability.md) — multi-ISA hosts
- [docs/usb.md](docs/usb.md) — usbVM broker (1→many)
- [docs/egress.md](docs/egress.md) — netVM / Nym / i2p / Tor
- [docs/nym-bootstrap.md](docs/nym-bootstrap.md)
- [docs/ADMIN-RECOVER.md](docs/ADMIN-RECOVER.md)

## Threat model (honest)

Stronger than a flat desktop, **not** Qubes. Goal: contain compromise to a zone. Closures **build**; runtime proof needs `switch` + `--live`.

| Resource | Model |
| --- | --- |
| **LAN** | Shared br-bunker → netVM |
| **Egress** | Only via netVM (killswitch) |
| **Nym** | One mixnet identity; per-zone SOCKS frontends |
| **USB** | usbVM broker → usbip; one live holder per device |

## License

MIT — see [LICENSE](LICENSE).
