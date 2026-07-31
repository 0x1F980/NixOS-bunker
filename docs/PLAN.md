# NixOS-bunker — locked plan (Qubes philosophy, broad hardware)

## Goal

Hardened **KVM**/microVM workstation on **any Linux arch** NixOS supports.
Host is not an egress/browsing domain. Apps in zones. Assume correct use.

## Non-negotiable

1. **Broad hardware** — x86_64 · aarch64 · riscv64 (same flake; KVM not Xen)
2. **ISO/HVM zones** — QEMU per arch (`bunker` TUI `o` / `iso=`); foreign ISO via TCG
3. **Host clearnet LOCKED** — `bunker-host-net` (lo + `10.0.0.0/24`)
4. **Guest killswitch ON** + **netVM SOCKS-only** (no guest NAT/forward)
5. **No daily apps on host** · **mediated clipboard + file copy** · **USB via usbVM**
6. **Real Shufflecake** — `bunker-sflc bootstrap|unlock` (no stub)

## Operator UX

- Ratatui `bunker` — full CRUD (incl. color, kind, net, hide, iso, panic)
- kinds: appvm | disposable | template (incl. **netVM / usbVM brokers** via TUI `t`)
- panic: keep | lock | wipe
- invisible + Shufflecake (hidden names only inside SFLC layers; public zones.json clean)
- disposable brokers: wipe disk on each start

## Rebuild (pick YOUR arch)

```bash
sudo bunker-host-net allow
sudo nixos-rebuild switch --flake .#host-x86_64-linux    # PC
sudo nixos-rebuild switch --flake .#host-aarch64-linux   # ARM
sudo nixos-rebuild switch --flake .#host-riscv64-linux   # RISC-V
# legacy alias: .#host == x86_64
sudo bunker-host-net lock
```

## Done / do

- [x] Full CRUD TUI + ISO
- [x] Multi-arch flake + hardware overlays + arch-aware iso-run
- [x] Host lock + killswitch default
- [x] Real Shufflecake + mediated `bunker-file` copy
- [ ] Live verify on each arch after rebuild
- [ ] riscv64: confirm nixpkgs package set (GNOME/nym) on target board

## Docs

- `docs/USER-GUIDE.md` — operator  
- `docs/DEV-GUIDE.md` — tree / LOC / change map  
- `docs/ARCHITECTURE.md` — vision + short model  

## Non-goals

- Xen/Qubes compatibility
- Host browsing / host Metadata Cleaner
- Voice broker (voice anonymizer lives in **personal** via Easy Effects)
