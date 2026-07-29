# bunker-deniable-tui

Ratatui CRUD for **whole hidden zone-VMs** on Shufflecake layers.
Launcher: **deniable · service** (`bunker-deniable`).

| Key | Action |
| --- | --- |
| a | Add deniable zone |
| Enter | Edit (layer, panic, template, …) |
| u | Unlock layer (passphrase → show VMs) |
| L | Lock all (hide VMs) |
| w | Save `deniable-zones.json` |
| x | Delete |
| ? | Help |

After save: `sudo nixos-rebuild switch --flake .#host` so guest closures exist.
Docs: [docs/deniable.md](../../docs/deniable.md).
