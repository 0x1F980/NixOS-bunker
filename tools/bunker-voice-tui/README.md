# bunker-voice-tui

Ratatui UI for **voiceVM mic anonymizer 1→many** defaults in `zones.json`.
Host launcher: **voice · service** (`bunker-voice`).

Engine (on voiceVM `10.0.0.3`):
- **Chimera** — speaker-irreversible anonymisation (preferred when installed)
- **anon** — sox pitch/band fallback (same idea as MorphMic `anonymous`)

| Key | Action |
| --- | --- |
| `1` | Voice defaults list |
| Space / Enter | Cycle `none` → `anon` → `chimera` |
| `a` | Attach/detach zone Pulse → voiceVM now |
| `v` | Start voiceVM |
| `w` | Save zones.json |
| `?` | Help |

See [docs/voice.md](../../docs/voice.md).
