# NixOS-bunker — architecture

**Repo:** https://github.com/0x1F980/NixOS-bunker  
**Stack:** NixOS 26.05 · microvm.nix · **KVM** · **x86_64 / aarch64 / riscv64**  
**Idea:** Qubes-like compartmentalization, **not** Qubes OS (no Xen — Xen is hardware-narrow).

**Code size (nix + sh + rs):** **~2371 LOC**.

---

## 1. One-sentence model

A thin GNOME host runs **one operator TUI** (`bunker`). Daily apps run in **microVM zones** (or **ISO/HVM**). Clearnet goes through **netVM** (nym / i2p / tor). USB through **usbVM**. Zones have **color** (icon + terminal), **kind**, **invisible**, **panic**.

---

## 1b. Security model (Qubes philosophy)

Assume correct use. No fluff.

| Rule | Mechanism |
| --- | --- |
| Host is not a browsing/egress domain | `bunker-host-net` — OUTPUT drop except lo + `10.0.0.0/24` |
| Temporary host WAN only for updates | `bunker-host-net allow` → rebuild → `lock` |
| App guests never clearnet-direct | `bunker-killswitch` ON at boot (only `vm-net` may WAN) |
| No daily apps on host | thin GNOME + disk/analyse tools; no mat2 on host |
| Clipboard mediated | `bunker-clip` |
| File copy mediated | `bunker-file` / TUI `f` (host staging + shred) |
| Invisible storage | **real Shufflecake** (`bunker-sflc bootstrap\|unlock`) |
| USB mediated | usbVM + usbip |

Host DNS default: `10.0.0.1` (netVM). Compromise of one zone ≠ host browsing stack.

---

## 2. Diagram

```
┌──────── HOST (clearnet LOCKED — lo + bunker LAN only) ────────────────┐
│  bunker (ratatui) · colored launchers · disk tools (no mat2)         │
│  br-bunker 10.0.0.254/24 · bunker-host-net · killswitch ON           │
│                                                                        │
│  Brokers: netVM .1 (nym/i2p/tor SOCKS 1→many) · usbVM .2 (1→many)    │
│  Zones: appvm|disposable|template · optional ISO · invisible · panic   │
└────────────────────────────────────────────────────────────────────────┘
```

### TUI keys (full CRUD)
`a` add · `d` del · `r` rename · `c` color · `t` type · `n` net · `i` hide · `o` iso · Space panic · `p` ARM · `w` save

**Color (`c` in TUI / `color=` in CRUD):**
- Host GNOME launcher SVG (rebuild after change)
- `bunker-term <zone>` — OSC bg/fg + PS1 from live `zones.json`
- In-guest login shell PS1/OSC — baked at zone build (`mk-app-zone`); rebuild zone after color change

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
| Hypervisor | Xen | **KVM** (broad hardware; not Xen) |
| CPU arches | mostly x86_64 | **x86_64 · aarch64 · riscv64** (same flake) |
| ISO / HVM | HVM | **QEMU ISO zones** (native KVM or TCG) |
| OS glue | Fedora/etc. | **NixOS flake** (reproducible) |

Same **security idea** (compromise one zone ≠ whole machine). Different **implementation** and UX.

---

## 4. Source of truth

| File | Role |
| --- | --- |
| `config/zones.json` | Zones: apps, mem, diskGb, kind, color, internet, usb, invisible, layer, panic |
| `config/zones.nix` | `builtins.fromJSON` of that file |
| `config/colors.nix` | Label palette (hex/ansi/bg) |
| `config/shufflecake.json` | Shufflecake image/device, `image_gb`, `max_layers` |
| `templates/*.nix` | Package sets: desktop, browser, dev, radio |
| `flake.nix` | `.#host-<arch>-linux` + `.#zone-<name>` (per system) |
| `hardware/` | KVM overlays: x86_64 / aarch64 / riscv64 |
| `modules/iso-qemu.nix` | Host QEMU + `/etc/bunker/qemu.env` for ISO |

After editing `zones.json`:  
`sudo nixos-rebuild switch --flake .#host-<arch>-linux`  
(`host-x86_64-linux` / `host-aarch64-linux` / `host-riscv64-linux`; alias `.#host` = x86_64)  
then `bunker-zone-start <zone>` (ISO zones use arch-aware `iso-run.sh`).

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
| `invisible` + `layer` | Hidden until `bunker-sflc unlock <layer>` |
| `panic` | `keep` \| `lock` \| `wipe` |

Invisible zones are omitted from static GNOME launchers; after unlock, desktop files appear under `/run/bunker/xdg`.

### 5.4 Operator UI (`bunker`)

Rust/ratatui — one screen for non-experts:

| Key | Action |
| --- | --- |
| `↑↓` / `j` `k` | Select zone |
| `n` | Cycle internet `tor` ↔ `none` |
| `i` | Toggle invisible (sets `layer=1`) |
| `Space` | Cycle panic `keep` → `lock` → `wipe` |
| `p` | Arm panic (type code, Enter) |
| `w` | Save `zones.json` |
| `q` | Quit |

CLI still exists for CRUD: `bunker-zone list|add|set|rm|apps|usb|…`.

### 5.5 Panic & invisible

- `bunker-panic`: checks `PANIC_HASH` → shreds zones with `panic=wipe` → `bunker-sflc lock all` → best-effort RAM wipe.
- `keep` / `lock`: not wiped; lock path mainly hits invisible layers via global lock.
- Shufflecake: real `dm_sflc` — `bunker-sflc bootstrap` once, then unlock (see `docs/deniable.md`).

### 5.6 Clipboard & file copy

- Clipboard: `bunker-clip send|copy|clear` (TTL clear).
- Files: `bunker-file copy|put|get` or TUI `f` — host staging under `/var/lib/bunker/file-xfer`, shredded after.

---

## 6. Operator cheat sheet

```bash
# Updates (host WAN temporarily open; lock again after)
sudo bunker-host-net allow
sudo nixos-rebuild switch --flake .#host-x86_64-linux   # or aarch64 / riscv64
sudo bunker-host-net lock

bunker                          # TUI
bunker-zone-start net
bunker-zone-start personal
bunker-term personal            # color from zones.json
bunker-usb-attach radio 0bda:2838
bunker-clip send personal
bunker-sflc unlock 1            # passphrase on stdin
bunker-panic                    # or TUI → p
bunker-host-net status
bunker-killswitch status        # ON by default at boot
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

voiceVM · vault guest · metadata system flag · four old TUIs · fat templates · zone cursors · Xen.

**Kept / required:** multi-arch KVM · ISO/HVM QEMU · nym/i2p/tor · ratatui `bunker` · colored launchers.

---

## 9. Honest limits

- Not Xen/Qubes TCB; KVM + nftables + thin host. Correct use assumed.
- Host lock is OUTPUT filter — operator can still `allow` for updates; don't leave it open.
- Shufflecake needs `bootstrap` once; Secure Boot may block unsigned `dm_sflc`.
- Panic RAM wipe is userspace best-effort.
- **riscv64 / some aarch64 boards:** flake targets exist; individual nixpkgs attrs (GNOME, nym, …) may lag — fix on that board, don't drop the arch.
- Live proof = rebuild on real hardware per arch.

---

## 10. Related docs

- `docs/PLAN.md` — locked plan / checklist  
- `docs/MANUAL.txt` / `man bunker` — commands  
- `docs/deniable.md` — invisible + panic  
- `docs/egress.md` — Tor  
- `docs/usb.md` — usbVM  
- `docs/ADMIN-RECOVER.md` — passwords / SSH  
