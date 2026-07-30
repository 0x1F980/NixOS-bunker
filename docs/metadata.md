# Metadata stripper (mat2)

When a zone has **`metadata: true`**, the guest gets **[mat2](https://github.com/jvoisin/mat2)** (Metadata Anonymisation Toolkit 2) plus a thin **`bunker-mat`** wrapper (`mat2 --inplace`).

This is an **in-zone tool**, not a broker VM — unlike net/usb/voice.

## On / off

**defaults · service** (`bunker-broker`) → key **`4`**, or:

```bash
bunker-zone set personal metadata=on
bunker-zone set work metadata=off
```

After changing the flag, rebuild guests so packages land in the zone:

```bash
sudo nixos-rebuild switch --flake .#host
bunker-zone-start personal
```

## Usage inside the zone

```bash
mat2 photo.jpg                 # report / write cleaned copy
bunker-mat photo.jpg doc.pdf   # inplace strip (wrapper)
mat2 --list                    # supported formats
```

## Notes

- Off by default on demo zones.
- Host also ships `mat2` / `bunker-mat` for emergency stripping when VMs are down.
- Sister defaults: net / usb / voice in the same TUI.
