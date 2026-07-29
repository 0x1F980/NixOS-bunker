# Voice broker (voiceVM)

Same idea as **netVM** / **usbVM**: **one broker VM → many app zones**.

Physical mic → **voiceVM** (`10.0.0.3`) → Chimera (or sox fallback) → Pulse TCP → zones with **`voice: true`**.

## Per-zone control (on/off only)

Use **defaults · service** (`bunker-broker`) → key **`3`**, or:

```bash
bunker-zone set personal voice=on
bunker-zone set work voice=off
```

No per-zone engine choice — anonymizer is global on voiceVM.

## Operator

```bash
bunker-zone-start voice
bunker-broker                 # 3 = voice on/off
bunker-voice-attach personal  # optional immediate tunnel
bunker-voice-detach personal
```

On zone start, `voice: true` auto-runs attach.

## Limits (honest)

- Chimera preferred when installed on voiceVM; sox fallback is weaker.
- Software presence is not deniable.
- Trust voiceVM for the anonymized stream.

Sister defaults: net/usb in the same TUI.
