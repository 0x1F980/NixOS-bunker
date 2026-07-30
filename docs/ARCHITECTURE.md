# NixOS-bunker — architecture

**Repo:** https://github.com/0x1F980/NixOS-bunker  
**Stack:** NixOS 26.05 · microvm.nix · KVM · x86_64 only  
**Idea:** Qubes-like compartmentalization, **not** Qubes OS (no Xen, no Qubes Manager).

**Code size (nix + sh + rs):** **~2371 LOC**.

---

## 1. One-sentence model

A thin GNOME host runs **one operator TUI** (`bunker`). Daily apps run in **microVM zones** (or **ISO/HVM**). Clearnet goes through **netVM** (nym / i2p / tor). USB through **usbVM**. Zones have **color** (icon + terminal), **kind**, **invisible**, **panic**.

---

## 2. Diagram

```
┌────────────────────────── HOST (thin GNOME) ──────────────────────────┐
│  bunker (ratatui) · farvede launchers · disk/analyse tools (no mat2) │
│  br-bunker 10.0.0.254/24                                              │
│                                                                        │
│  Brokers: netVM .1 (nym/i2p/tor SOCKS 1→many) · usbVM .2 (1→many)    │
│  Zones: appvm|disposable|template · optional ISO · invisible · panic   │
└────────────────────────────────────────────────────────────────────────┘
```

### TUI keys (full CRUD)
`a` add · `d` del · `r` rename · `c` color · `t` type · `n` net · `i` hide · `o` iso · Space panic · `p` ARM · `w` save

Color = host icon + zone terminal. After color/rename: rebuild for GNOME icons.

---

## 3. Like Qubes? / not Qubes?

| Concept | Qubes | Bunker |
| --- | --- | --- |
| Isolation unit | AppVM (Xen) | Zone (KVM microVM) |
| Admin domain | dom0 | Host NixOS (GNOME thin) |
| Network broker | netVM | netVM (Tor) |
| USB broker | usbVM | usbVM (usbip) |
| Labels | colors | `color` + SVG icons + `bunker-term` |
| Disposable | DisposableVM | `kind=disposable` + `bunker-wipe` |
| Template | TemplateVM | `templates/*.nix` package sets |
| Policy UI | Qubes Manager | **`bunker` ratatui** + launchers |
| Hypervisor | Xen | **KVM only** |
| OS glue | Fedora/etc. | **NixOS flake** (reproducible) |

Same **security idea** (compromise one zone ≠ whole machine). Different **implementation** and UX.

---

## 4. Source of truth

| File | Role |
| --- | --- |
| `config/zones.json` | Zones: apps, mem, diskGb, kind, color, internet, usb, invisible, layer, panic |
| `config/zones.nix` | `builtins.fromJSON` of that file |
| `config/colors.nix` | Label palette (hex/ansi/bg) |
| `config/shufflecake.json` | Invisible layers (`device`, `mount_root`, `mode`) — empty `device` = stub mode |
| `templates/*.nix` | Package sets: desktop, browser, dev, radio |
| `flake.nix` | Builds `.#host` + `.#zone-<name>` |

After editing `zones.json`:  
`sudo nixos-rebuild switch --flake .#host`  
then `bunker-zone-start <zone>`.

---

## 5. Components

### 5.1 Host

- GNOME stripped of consumer apps; emergency disk tools kept (Disks, nautilus, cryptsetup, …).
- Users: `bunker` (daily), `admin`/`root` (rebuild). Default passwords: see `docs/ADMIN-RECOVER.md`.
- Packages wrap scripts from `/etc/bunker/scripts`.
- Hardening: firewall, sysctl, AppArmor, no hibernate, no bluetooth/avahi/printing.

### 5.2 Brokers

- **netVM:** Tor client; per-zone SOCKS on `10.0.0.1:<socks>` → `127.0.0.1:9050`. DNS via unbound on LAN.
- **usbVM:** Physical USB attached here; zones pull via usbip (`bunker-usb-attach`).

### 5.3 Zones

Built by `modules/guests/mk-app-zone.nix` + template import.

| Field | Meaning |
| --- | --- |
| `kind` | `appvm` \| `disposable` \| `template` |
| `template` | Which `templates/<name>.nix` |
| `apps[]` | Extra nixpkgs attrs into the guest |
| `mem` / `vcpu` / `diskGb` | Limits on the **zone** (not per-app) |
| `internet` | `tor` \| `none` |
| `usb[]` | Default VID:PID list auto-attached on start |
| `color` | Host icon + shell tint |
| `invisible` + unique `layer` + `hideHash` | Hidden until `bunker-sflc unlock-zone <name>` (or TUI `u`) |
| `panic` | `keep` \| `lock` \| `wipe` |

Invisible zones are omitted from static GNOME launchers; after unlock, desktop files appear under `/run/bunker/xdg`.

### 5.4 Operator UI (`bunker`)

Rust/ratatui — one screen for non-experts:

| Key | Action |
| --- | --- |
| `↑↓` / `j` `k` | Select zone |
| `n` | Cycle internet `tor` ↔ `none` |
| `i` | Toggle invisible (unique free layer + passphrase → `hideHash`) |
| `u` / `l` | Unlock / lock **this** hidden zone only |
| `a` / `r` / `d` / `c` | Add / rename / delete / cycle color |
| `Space` | Cycle panic `keep` → `lock` → `wipe` |
| `p` | Arm panic (type code, Enter) |
| `w` | Save `zones.json` |
| `q` | Quit |

CLI still exists for CRUD: `bunker-zone list|add|set|rm|apps|usb|…`.

### 5.5 Panic & invisible

- `bunker-panic`: checks `PANIC_HASH` → shreds zones with `panic=wipe` → `bunker-sflc lock all` → best-effort RAM wipe.
- `keep` / `lock`: not wiped; lock path mainly hits invisible layers via global lock.
- Per-zone hide: each invisible zone has its own layer + passphrase (`hideHash`).
- Shufflecake: research-grade; without `device` in `shufflecake.json`, unlock uses a **stub** layer dir (honest deniability limits — see `docs/deniable.md`).

### 5.6 Clipboard

Mediated only: `bunker-clip send|copy|clear`. No guest→host path. Zone clipboard TTL clear (default 30s).

---

## 6. Operator cheat sheet

```bash
sudo nixos-rebuild switch --flake .#host
bunker                          # TUI
bunker-zone-start net
bunker-zone-start personal
bunker-term personal
bunker-usb-attach radio 0bda:2838
bunker-clip send personal
bunker-sflc unlock-zone secret  # passphrase on stdin (this zone only)
bunker-sflc unlock 1              # legacy: whole layer
bunker-panic                    # or TUI → p
bunker-killswitch enable
bunker-wipe browse
bunker-test-isolation
```

---

## 7. Lines of code (sorted ascending)

**Total ~2113** (`*.nix` + `*.sh` + `*.rs`).

| LOC | Path |
| ---: | --- |
| 3 | `config/zones.nix` |
| 9 | `modules/clipboard-oneway.nix` |
| 10 | `scripts/usb-detach.sh` |
| 11 | `templates/dev.nix` |
| 12 | `templates/radio.nix` |
| 13 | `hardware/generic-x86_64.nix` |
| 13 | `scripts/zone-term.sh` |
| 13 | `templates/browser.nix` |
| 16 | `scripts/zone-wipe.sh` |
| 16 | `tools/bunker-tui/default.nix` |
| 17 | `templates/desktop.nix` |
| 21 | `scripts/test-isolation.sh` |
| 27 | `scripts/lib-shufflecake.sh` |
| 28 | `scripts/usb-attach.sh` |
| 35 | `scripts/bunker-panic.sh` |
| 36 | `modules/zones-registry.nix` |
| 42 | `hosts/bunker/configuration.nix` |
| 42 | `scripts/killswitch.sh` |
| 43 | `hosts/bunker/hardware-configuration.nix` |
| 44 | `scripts/lib-common.sh` |
| 51 | `config/colors.nix` |
| 51 | `modules/shufflecake-deniable.nix` |
| 53 | `scripts/clipboard.sh` |
| 57 | `modules/zones-ui.nix` |
| 65 | `modules/hardening.nix` |
| 66 | `scripts/zone-start.sh` |
| 84 | `modules/microvm-network.nix` |
| 93 | `modules/guests/mk-app-zone.nix` |
| 101 | `flake.nix` |
| 107 | `modules/guests/microvm-base.nix` |
| 112 | `modules/guests/net.nix` |
| 128 | `scripts/bunker-sflc.sh` |
| 134 | `scripts/bunker-zone.sh` |
| 145 | `modules/guests/usb.nix` |
| 162 | `modules/host-minimal.nix` |
| 253 | `tools/bunker-tui/src/main.rs` |

### By area

| LOC | Area |
| ---: | --- |
| 921 | `modules/` (incl. guests) |
| 617 | `scripts/` |
| 457 | `modules/guests/` alone |
| 253 | `tools/bunker-tui/src` |
| 134 | `config/` |
| 101 | `flake.nix` |
| 85 | `hosts/` |
| 53 | `templates/` |
| 13 | `hardware/` |

Largest intentional chunks: **TUI (UX)**, **usb guest**, **zone CRUD**, **sflc**, **host shell**, **netVM**.

---

## 8. What was deliberately removed

voiceVM · vault guest · ISO/HVM QEMU · i2p · nym-client · metadata system flag · multi-arch · four old TUIs · fat templates · zone cursors.

Kept for “dumb user” UX: **ratatui `bunker`** + colored GNOME launchers.

---

## 9. Honest limits

- Stronger than a flat desktop; **not** a Qubes clone or Xen TCB story.
- Tor egress is simple and maintainable; not a full mixnet stack.
- Invisible/Shufflecake needs a real `device` or it is stub.
- Panic RAM wipe is userspace best-effort.
- This agent environment may lack `nix`/KVM — full proof = rebuild on the bunker machine.

---

## 10. Related docs

- `docs/MANUAL.txt` / `man bunker` — commands  
- `docs/deniable.md` — invisible + panic  
- `docs/egress.md` — Tor  
- `docs/usb.md` — usbVM  
- `docs/ADMIN-RECOVER.md` — passwords / SSH  
