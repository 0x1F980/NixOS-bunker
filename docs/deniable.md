# Invisible zones (real Shufflecake)

Hidden units are **whole zones** (VMs). Storage is **Shufflecake** (`dm_sflc`), not a stub dir.

## Setup (once)

```bash
# Default image: /var/lib/bunker/sflc.img (32G sparse) — or set block device in config/shufflecake.json
sudo bunker-sflc bootstrap          # interactive passphrases for layers 1..N
# or: printf 'p1\np2\np3\n' | sudo bunker-sflc bootstrap
```

`max_layers` / `image_gb` / `device` live in `config/shufflecake.json` (then rebuild host).

## Daily

| Action | Command / TUI |
| --- | --- |
| Hide zone | TUI `i` → `invisible` + `layer` · `w` save · rebuild |
| Unlock | TUI `u` or `echo pass \| sudo bunker-sflc unlock <layer>` |
| Lock | `sudo bunker-sflc lock all` |
| Status | `bunker-sflc status` |

Unlocking layer **L** opens Shufflecake volumes **0..L-1** (lesser secrecy included), mounts them under `/mnt/bunker-sflc/layer*`, and symlinks invisible zone disks there.

## Panic

`bunker` → `p`, or `bunker-panic`: wipe `panic=wipe` zones → `bunker-sflc lock all` → best-effort RAM wipe.

## Honesty

- Shufflecake is research-grade; presence of the *tool* on disk is not deniable.
- Secure Boot may block unsigned `dm_sflc` — disable SB or sign the module.
- Always unlock your highest daily layer when writing (corruption risk on unopened higher layers).
