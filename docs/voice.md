# Voice broker (voiceVM)

Same idea as **netVM** / **usbVM**: **one broker VM → many app zones**.

App you meant is likely **[Chimera](https://pypi.org/project/chimera-voice/)** (local, speaker-irreversible anonymisation) or **[MorphMic](https://pypi.org/project/morphmic/)** (`anonymous` profile). voiceVM prefers Chimera; falls back to a sox “anonymous” chain.

## Model

```
[physical mic] --> [voiceVM 10.0.0.3] --Chimera/sox--> [Pulse tcp :4713] --> [app zones]
```

1. Start broker: `bunker-zone-start voice` (or **voice · service** → `v`)
2. Set per-zone default: **voice · service** / `bunker-voice` → `voice=anon|chimera|none`
3. On zone start (or `bunker-voice-attach <zone>`): zone uses `PULSE_SERVER=tcp:10.0.0.3:4713`

## Operator

```bash
bunker-zone-start voice
bunker-voice          # ratatui 1→many defaults
bunker-zone set personal voice=chimera
bunker-voice-attach personal
bunker-voice-detach personal
```

USB headset: attach to **voice** via usbVM/QMP policy (mic stays off AppVMs).

## Limits (honest)

- Chimera must be installed on voiceVM for full crypto anonymisation; sox fallback is weaker.
- Presence of anonymizer software is not deniable.
- Network Pulse on bunker LAN only — still trust voiceVM.

Defaults TUI sister: [bunker-broker-tui](../tools/bunker-broker-tui/) (net/usb).
