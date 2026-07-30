# Invisible zones (Shufflecake)

Hidden units are **whole zones** (VMs), not files or apps.

## Model

| Kind | Where | GNOME |
| --- | --- | --- |
| Normal zone | `zones.json` `invisible=false` | Always shown |
| Invisible zone | `zones.json` `invisible=true` + unique `layer` + optional `hideHash` | Only after that zone is unlocked |

Fields:

```json
"invisible": true,
"layer": 2,
"hideHash": "<sha256 of this zone's passphrase>",
"panic": "wipe"
```

Each invisible zone gets its **own layer** and **own passphrase** (set in the TUI with `i`). Unlocking one zone does **not** unlock the others — plausible deniability stays per zone.

`panic`: `keep` | `lock` | `wipe` (per zone).

Unlock: `bunker` TUI (`i` hide → passphrase, then `u` unlock / `l` lock) or CLI:

```bash
bunker-sflc unlock-zone secret   # passphrase on stdin
bunker-sflc lock-zone secret
```

Legacy layer unlock (`bunker-sflc unlock <n>`) still works and reveals every zone on that layer.

Panic: `bunker` → Panic (`p`), or `bunker-panic`. Wipes zones with `panic=wipe`, locks layers, best-effort RAM wipe.

## Honesty

- Shufflecake in nixpkgs is research-grade.
- Software presence on disk is **not** deniable.
- Userspace RAM wipe is not a cold-boot guarantee.
