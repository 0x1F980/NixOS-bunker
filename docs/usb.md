# USB broker (usbVM)

Same idea as **netVM** for network: **one broker VM → many app zones**.

## Model

```
[physical USB] --QMP--> [usbVM 10.0.0.2] --usbip--> [app zone A|B|C…]
```

1. Host attaches the physical device **only** to `usb` (QMP `usb-host`).
2. `usbipd` on usbVM exports it (`bunker-usb-broker bind`).
3. Target zone imports: `usbip attach -r 10.0.0.2 -b <busid>`.

## Operator

```bash
bunker-zone-start usb          # broker must be up
bunker-zone-start radio
bunker-usb-attach radio 0bda:2838
bunker-usb-detach radio 0bda:2838   # device stays on usbVM for next zone
bunker-usb-attach personal 0bda:2838  # moves live holder
```

Zone defaults in `config/zones.json` `"usb": ["vid:pid"]` auto-run attach on `bunker-zone-start`.

## Limits (honest)

- Hardware: **one** live consumer per physical device.
- Listing the same VID:PID on many zones is fine; attach **moves**.
- Needs working SSH `zone@` into usb + app zone (same as other bunker tools).
- Not Qubes USBProxy; compromise of a zone with a live device can talk to that device.
