# bunker-zones-tui

Ratatui UI for **AppVM / Disposable CRUD** in `config/zones.json`.
Host launcher: **zones · service** (`bunker-zones`).

Prefer this (or `bunker-zone` CLI) over hand-editing Nix modules for per-zone changes.
Hand-editing `zones.json` is fine — same source of truth. After save: `nixos-rebuild switch`.

## Keys

| Key | Action |
| --- | --- |
| ↑↓ / j k | Navigate list |
| Enter / e | Edit selected zone |
| a | Add zone (name prompt) |
| x | Delete zone (confirm y) |
| s | Start selected (`bunker-zone-start`) |
| w | Write `zones.json` |
| t / c / i / k / m | Cycle template / color / internet / kind / mem |
| p / P | Add / pop app package |
| u / U | Add / pop USB vid:pid |
| ? | Help |
| q / Esc | Quit / back |

Sister app: [bunker-broker-tui](../bunker-broker-tui/) (**defaults · service**) for net/usb brokers.
