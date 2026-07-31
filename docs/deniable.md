# Invisible zones (real Shufflecake — plausible deniable)

Hidden units are **whole zones** (friendly names). Storage and **zone identity** live only inside Shufflecake layers. Public `config/zones.json` must never list them.

## Model

| Public (always) | After unlock layer L |
| --- | --- |
| `zones.json` — visible VMs only | `/mnt/bunker-sflc/layerL/hidden-zones.json` |
| `slots.json` — anonymous `d1..dN` runners | TUI merges friendly name → slot |
| No secret zone names | Start `radio` → `microvm@d1` |

## Setup (once)

```bash
sudo bunker-sflc bootstrap          # N layer passphrases on stdin
# optional interactive: create a deniable hidden zone (name + slot) — stored ONLY in the layer
```

`max_layers` / `image_gb` / `device` live in `config/shufflecake.json` (then rebuild host).

## Daily

| Action | Command / TUI |
| --- | --- |
| Unlock | TUI `u` or `echo pass \| sudo bunker-sflc unlock <layer>` — hidden names appear |
| Hide zone | Unlock first → TUI `i` (assigns free slot) → `w` save |
| Start | TUI `s` on friendly name (runs the slot VM) |
| Lock | `sudo bunker-sflc lock all` — hidden names vanish from TUI |

## Panic

`bunker` → `p`, or `bunker-panic`:

| Mode | Effect |
| --- | --- |
| keep | leave zone data |
| lock | stop those zone VMs |
| wipe | shred zone disks (+ layer files if wipe+hidden) |

Then lock all Shufflecake layers + best-effort RAM wipe.

## Honesty (what PD does and does not claim)

**When layers are locked:**

- No friendly hidden names in public `zones.json` / TUI / GNOME launchers
- Zone disks for hidden VMs are ciphertext inside the cake

**Still visible on the host (not deniable):**

- Shufflecake tool + `dm_sflc` + image file presence
- Anonymous capacity `d1..dN` in the flake / nix store
- Templates such as `radio.nix` in a git checkout under `$HOME` if you leave the repo there

**Ops note:** editable public registry on the host is `/var/lib/bunker/zones.json` (seeded from `/etc/bunker/zones.json`). Do not expect `/etc/bunker/zones.json` to be writable.
