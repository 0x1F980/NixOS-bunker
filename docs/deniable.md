# Invisible zones (Shufflecake)

Hidden units are **whole zones** (VMs), not files or apps.

## Model

| Kind | Where | GNOME |
| --- | --- | --- |
| Normal zone | `zones.json` `invisible=false` | Always shown |
| Invisible zone | `zones.json` `invisible=true` + `layer` | Only after `bunker-sflc unlock <layer>` |

Fields:

```json
"invisible": true,
"layer": 1,
"panic": "wipe"
```

`panic`: `keep` | `lock` | `wipe` (per zone). Password is **per layer**, not per zone.

Unlock: `bunker` TUI or `bunker-sflc unlock 1` (passphrase on stdin).

Panic: `bunker` → Panic, or `bunker-panic`. Wipes zones with `panic=wipe`, locks layers, best-effort RAM wipe.

## Honesty

- Shufflecake in nixpkgs is research-grade.
- Software presence on disk is **not** deniable.
- Userspace RAM wipe is not a cold-boot guarantee.
