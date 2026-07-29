# Deniable whole-zone VMs (Shufflecake)

Hidden units are **entire microVMs**, not files inside a public zone.

## Model

| Kind | Registry | GNOME |
| --- | --- | --- |
| Public / decoy | `config/zones.json` | Always in AppVMs / Disposables |
| Deniable | `config/deniable-zones.json` | Only while layer unlocked (`/run/bunker/xdg`) |

Unlock/lock: **deniable · service** (`bunker-deniable`) → `bunker-sflc unlock|lock`.
Disk path when unlocked: `/mnt/bunker-sflc/layerN/microvms/<name>` (symlinked from `/var/lib/microvms/<name>`).

## Config

- [`config/shufflecake.json`](../config/shufflecake.json) — `device`, `mount_root`, `mode` (`auto`|`stub`|`shufflecake`)
- [`config/deniable-zones.json`](../config/deniable-zones.json) — zone fields + `layer` + `panic`
- Panic hash: `/etc/bunker/panic.conf` (`PANIC_HASH`, default passphrase `changeme`)

Set a real Shufflecake block device in `shufflecake.json` when ready. Empty `device` uses **stub** layer dirs (UX + wiring; not forensic PD).

## Panic · service

☢ **panic · service** asks for the panic code, then `bunker-panic`:

1. Stops zones with `"panic": true`
2. Shreds their unlocked data / layer crumbs / `/var/lib/bunker/sflc-keys/*layerN*`
3. Locks all deniable layers (hides VMs)
4. Best-effort RAM wipe (`sdmem`) — **reboot after**

Does **not** wipe public decoy zones or host root LUKS (that would destroy plausible deniability).

## Honesty

- Shufflecake in nixpkgs is research-grade; this integration is best-effort.
- Presence of bunker/Shufflecake software on disk is **not** deniable.
- Userspace RAM wipe is **not** a guarantee against cold-boot with physical access.
- Prefer **deniable · service** / **panic · service** over hand-editing Nix modules.

See also: [usb.md](usb.md), [egress.md](egress.md), `man bunker`.
