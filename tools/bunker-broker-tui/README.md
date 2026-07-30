# bunker-broker-tui

Ratatui UI for **net + USB + voice + metadata (mat2) defaults** in `config/zones.json`.
Host launcher: **defaults · service** (`bunker-broker`).

## Keys

| Key | Action |
| --- | --- |
| `1` | Net / egress defaults |
| `2` | USB defaults |
| `3` | Voice anonymized mic **on/off** per zone |
| `4` | Metadata / mat2 EXIF stripper **on/off** per zone |
| `n` / `u` / `v` | Start netVM / usbVM / voiceVM |
| `w` | Write `zones.json` |
| Space / Enter | Cycle net / toggle voice or metadata |
| `a` / `d` | USB add/delete; on voice screen `a` = attach now |
| `?` | Help |
| `q` / Esc | Quit / back |

Voice engine (Chimera/sox) runs on **voiceVM** only — zones only choose on/off.
Metadata ships **mat2** into the zone when on (no metadataVM).

See [docs/usb.md](../../docs/usb.md), [docs/egress.md](../../docs/egress.md), [docs/voice.md](../../docs/voice.md), [docs/metadata.md](../../docs/metadata.md).
