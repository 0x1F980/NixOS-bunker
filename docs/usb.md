# USB via usbVM

Physical USB → **usbVM** (`10.0.0.2`) → attach to one zone at a time.

```bash
bunker-usb-attach radio 0bda:2838
bunker-usb-detach radio 0bda:2838
```

Defaults in `zones.json` `"usb": ["vid:pid"]` auto-attach on start.
