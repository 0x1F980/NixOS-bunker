# NixOS-bunker — developer guide

How the tree is laid out, what to edit, and current size (~**3670** LOC nix+sh+rs, commit-era snapshot).

---

## 1. Layout

```
flake.nix                 # hosts + guests per system
config/                   # SoT: zones.json, shufflecake.json, colors.nix
hosts/bunker/             # host NixOS entry + hardware stub
hardware/                 # KVM overlays x86_64 / aarch64 / riscv64
modules/                  # host + guest modules
  guests/                 # net, usb, microvm-base, mk-app-zone
scripts/                  # operator CLIs (installed to /etc/bunker/scripts)
templates/                # guest package sets (desktop, browser, …)
tools/bunker-tui/         # ratatui CRUD
docs/                     # USER / DEV / ARCHITECTURE + deep dives
```

---

## 2. Flake targets

| Attr | Meaning |
| --- | --- |
| `.#host-x86_64-linux` | Host build (PC) |
| `.#host-aarch64-linux` | Host build (ARM) |
| `.#host-riscv64-linux` | Host build (RISC-V) |
| `.#host` | Alias → x86_64 |
| `.#zone-<name>` / `packages.<sys>.zone-<name>` | Guest runners |

Always pick **your** arch. Multi-arch is intentional (not Xen).

---

## 3. Where to change what

| Goal | Touch |
| --- | --- |
| Zone policy (apps, color, net, hide…) | `config/zones.json` + TUI / `bunker-zone` |
| Host packages / GNOME thinness | `modules/host-minimal.nix` |
| Host clearnet lock | `modules/host-net-lock.nix`, `scripts/bunker-host-net.sh` |
| Guest SOCKS / no-NAT | `modules/guests/net.nix`, `mk-app-zone.nix` |
| USB broker | `modules/guests/usb.nix`, `scripts/usb-*.sh` |
| Shufflecake | `modules/shufflecake-deniable.nix`, `scripts/bunker-sflc.sh` |
| File copy / clipboard | `scripts/file-copy.sh`, `clipboard.sh` |
| TUI | `tools/bunker-tui/src/main.rs` |
| ISO | `scripts/iso-run.sh`, `modules/iso-qemu.nix` |
| Killswitch | `scripts/killswitch.sh` (autostart in host-net-lock) |

After edits: rebuild host (and restart affected zones).

---

## 4. Security implementation notes

- **netVM is not a router.** `ip_forward=0`, no guest MASQUERADE, FORWARD DROP.  
- **Guests:** no default gateway; OUTPUT allowlist = SOCKS + DNS + usbVM.  
- **Host:** nft OUTPUT drop except lo + `10.0.0.0/24`.  
- **Mediation:** never mount guest FS for copy; SSH/scp staging + shred.

Do not reintroduce guest NAT “for convenience”.

---

## 5. Tests

```bash
bash scripts/test-isolation.sh    # static smoke (no KVM required)
```

Live proof = `nixos-rebuild` + run zones on real hardware.

---

## 6. File map — LOC & size

*Source: working tree. LOC = lines of `*.nix` / `*.sh` / `*.rs` (no Cargo `target`). Bytes = on-disk size.*

### By area

| Area | LOC | Role |
| ---: | ---: | --- |
| scripts/ | ~1280 | Operator CLIs |
| modules/ | ~1160 | NixOS modules (+ guests) |
| tools/bunker-tui/src | 783 | Ratatui |
| flake.nix | 155 | Flake |
| hosts/ | 87 | Host entry |
| hardware/ | 51 | Arch overlays |
| config/ | ~54 | SoT |
| templates/ | 53 | Guest pkgs |
| **Total code** | **~3670** | |

### Largest code files

| LOC | Bytes | Path |
| ---: | ---: | --- |
| 783 | 27k | `tools/bunker-tui/src/main.rs` |
| 302 | 9.2k | `scripts/bunker-sflc.sh` |
| 214 | 6.3k | `modules/guests/net.nix` |
| 173 | 4.9k | `scripts/file-copy.sh` |
| 161 | 4.2k | `modules/host-minimal.nix` |
| 157 | 6.8k | `scripts/bunker-zone.sh` |
| 155 | 4.3k | `flake.nix` |
| 145 | 3.5k | `modules/guests/usb.nix` |
| 136 | 5.1k | `scripts/iso-run.sh` |
| 129 | 4.0k | `modules/guests/mk-app-zone.nix` |
| 107 | 2.9k | `modules/guests/microvm-base.nix` |
| 88 | 3.0k | `scripts/lib-shufflecake.sh` |
| 84 | 2.4k | `modules/microvm-network.nix` |
| 81 | 2.6k | `modules/host-net-lock.nix` |
| 68 | 2.6k | `scripts/zone-start.sh` |
| 65 | 1.5k | `modules/hardening.nix` |
| 60 | 1.6k | `modules/shufflecake-deniable.nix` |
| 57 | 2.0k | `modules/zones-ui.nix` |
| 53 | 2.3k | `scripts/clipboard.sh` |
| 46 | 1.2k | `scripts/bunker-host-net.sh` |
| 42 | 1.1k | `scripts/killswitch.sh` |
| 40 | 2.8k | `scripts/test-isolation.sh` |
| 35 | 0.8k | `modules/iso-qemu.nix` |
| 35 | 2.0k | `scripts/bunker-panic.sh` |

### Docs (not counted in LOC total)

| Path | Purpose |
| --- | --- |
| `docs/ARCHITECTURE.md` | Vision + short model |
| `docs/USER-GUIDE.md` | Operator |
| `docs/DEV-GUIDE.md` | This file |
| `docs/egress.md` | SOCKS-only egress |
| `docs/deniable.md` | Shufflecake |
| `docs/file-copy.md` | Mediated files |
| `docs/usb.md` | usbVM |
| `docs/PLAN.md` | Locked goals |
| `docs/MANUAL.txt` | Short cheat sheet (`bunker-help`) |
| `docs/ADMIN-RECOVER.md` | Passwords |

### Config / host stubs

| Path | Notes |
| --- | --- |
| `config/zones.json` | Zone SoT |
| `config/shufflecake.json` | Default image `/var/lib/bunker/sflc.img` |
| `hosts/bunker/hardware-configuration.nix` | **Stub** — replace on target machine |

---

## 7. Conventions

- Prefer small scripts + thin Nix modules over new daemons.  
- One operator UI: `tools/bunker-tui` only.  
- Document security invariants in ARCHITECTURE / egress when you change them.  
- Smoke-test: extend `scripts/test-isolation.sh` for new invariants.
