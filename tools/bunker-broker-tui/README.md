# bunker-broker-tui

Ratatui UI for **net + USB + voice 1→many defaults** in `config/zones.json`.
Host launcher: **defaults · service** (`bunker-broker`).

## Keys

| Key | Action |
| --- | --- |
| `1` | Net / egress defaults |
| `2` | USB defaults |
| `3` | Voice anonymized mic **on/off** per zone |
| `n` / `u` / `v` | Start netVM / usbVM / voiceVM |
| `w` | Write `zones.json` |
| Space / Enter | Cycle net / toggle voice / (on usb: n/a) |
| `a` / `d` | USB add/delete; on voice screen `a` = attach now |
| `?` | Help |
| `q` / Esc | Quit / back |

Voice engine (Chimera/sox) runs on **voiceVM** only — zones only choose on/off.

See [docs/usb.md](../../docs/usb.md), [docs/egress.md](../../docs/egress.md), [docs/voice.md](../../docs/voice.md).
