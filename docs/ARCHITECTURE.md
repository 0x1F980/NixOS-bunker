# NixOS-bunker — architecture (short)

**Repo:** https://github.com/0x1F980/NixOS-bunker  
**Stack:** NixOS 26.05 · microvm.nix · KVM · x86_64 / aarch64 / riscv64  
**Not Qubes.** Same security *idea*; different hypervisor and UX.

---

## Vision

A workstation where **compromise of one app does not own the machine**.  
Daily work lives in **zones** (KVM VMs). The **host is not a browsing or clearnet domain**.  
Operator UX is a **single ratatui TUI** — not a heavy GUI.  
Hardware must stay **broad** (KVM, not Xen). Correct use assumed.

---

## Model (one glance)

```
HOST (clearnet LOCKED — lo + 10.0.0.0/24)
  bunker TUI · thin GNOME · disk tools only
  br-bunker 10.0.0.254/24 · killswitch ON
       │
       ├─ netVM  .1  — SOCKS broker only (nym/i2p/tor) · NO guest NAT
       ├─ usbVM  .2  — USB broker (usbip)
       └─ zones      — appvm | disposable | template | ISO
                      color · invisible/Shufflecake · panic
```

| Piece | Role |
| --- | --- |
| Host | Admin + orchestration; never daily apps |
| netVM | Proxy broker; `ip_forward=0`; guests SOCKS-only |
| usbVM | Physical USB → zones via usbip |
| Zone | One VM = one trust domain |
| TUI `bunker` | **All daily ops** for non-experts: start, USB, host-net, sflc boot, CRUD, files |
| Shufflecake | Hidden zone disks (real `dm_sflc`) |

---

## Security invariants

1. Host OUTPUT: lo + bunker LAN only (`bunker-host-net`)  
2. App guests: no default gateway · OUTPUT only SOCKS/DNS/usbVM  
3. netVM: no guest MASQUERADE / no IP forward  
4. Clipboard + files: mediated only (`bunker-clip`, `bunker-file`)  
5. USB: only via usbVM  

---

## Source of truth

| File | What |
| --- | --- |
| `config/zones.json` | Zones (apps, kind, color, net, hide, panic, iso…) |
| `config/shufflecake.json` | SFLC image/device, layers |
| `config/colors.nix` | Label palette |
| `flake.nix` | `.#host-<arch>-linux` + `.#zone-*` |

Edit → `w` in TUI (or CLI) → `nixos-rebuild switch --flake .#host-<arch>-linux` → start zones.

---

## Docs map

| Doc | Audience |
| --- | --- |
| [USER-GUIDE.md](USER-GUIDE.md) | Daily operator |
| [DEV-GUIDE.md](DEV-GUIDE.md) | Layout, LOC, how to change code |
| [egress.md](egress.md) · [deniable.md](deniable.md) · [file-copy.md](file-copy.md) · [usb.md](usb.md) | Deep dives |
| [PLAN.md](PLAN.md) | Locked goals / checklist |
| [ADMIN-RECOVER.md](ADMIN-RECOVER.md) | Passwords / recover |
