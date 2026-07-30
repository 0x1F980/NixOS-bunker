# ISO / HVM zones (Tails, other live ISOs, installed guests)

Zones with **`template: "iso"`** are **not** NixOS microVMs. They boot with QEMU
(`scripts/iso-run.sh`) from an `.iso` / disk image, but use the **same**
`zones.json` controls as AppVMs:

| Field | Meaning |
| --- | --- |
| `name` | Zone id / launcher title |
| `kind` | `appvm` \| `disposable` \| `template` |
| `color` | Label color (host icon + QEMU window name; **not** guest OS cursor) |
| `internet` | Intent + SOCKS port via netVM (`nym`/`i2p`/`tor`/`none`) |
| `usb` | Default `vid:pid` list (direct QMP attach for ISO guests) |
| `mem` / `vcpu` | QEMU RAM / CPUs |
| `iso` | Absolute path to media |
| `boot` | `iso` (default) \| `disk` \| `both` |
| `disk` / `diskGb` | Persistent qcow2 (appvm/template) |
| `display` | `gtk` (default) \| `spice` \| `none` |

## Add examples

```bash
# Disposable Tails (live, wipe overlay on exit)
bunker-zone add tails \
  --template iso \
  --iso /var/lib/bunker/isos/tails-amd64.iso \
  --kind disposable \
  --internet none \
  --color purple \
  --mem 4096 \
  --vcpu 4

# Persistent install (install OS to disk, then boot=disk)
bunker-zone add winbox --template iso --iso /var/lib/bunker/isos/something.iso --kind appvm
bunker-zone set winbox boot=both    # install
# later:
bunker-zone set winbox boot=disk

bunker-zone-start tails
```

Or **zones · service** (`bunker-zones`):

- **`A`** / **`I`** — add ISO/HVM (name → path wizard; defaults to disposable + `internet=none`)
- **`k`** — kind: appvm → disposable → template
- **`m`/`M`** — RAM ± · **`v`/`V`** — vCPU ± · **`r`/`N`** — type exact MiB / cores
- **`o`** — change ISO path · **`b`** — boot mode
- Same color / net / usb as NixOS zones (host icon + window title). Guest cursor stays the ISO’s own.

Deniable ISO: **deniable · service** — same **`A`/`I`** keys.

## Behaviour

- **disposable** — temporary disk + `-snapshot`; wiped when the QEMU process exits / `bunker-wipe`.
- **appvm** — persistent `disk.qcow2` under `/var/lib/bunker/iso-zones/<name>/`.
- **template** — same persistence as appvm; shown under Templates folder (base image you clone from later).
- **Network** — tap on `br-bunker` with zone MAC. Guest should use zone `ip`, gw `10.0.0.1`. SOCKS still published on netVM for guests that can set a proxy. Live distros with their own Tor (Tails) → prefer `internet=none`.
- **USB** — `bunker-usb-attach <zone> vid:pid` uses **direct QMP usb-host** (no usbip inside the guest).
- **GUI** — GTK window (`display=gtk`). No `bunker-term` SSH.
- **No flake rebuild** required to *run* an ISO zone after `zones.json` is saved; rebuild host if you want GNOME launchers updated.

## Layout

```
/var/lib/bunker/isos/           # your downloaded ISOs (suggestion)
/var/lib/bunker/iso-zones/<n>/  # qcow2 / overlays
/run/microvm/<n>.sock           # QMP (same path as microVMs)
```

## Limits (honest)

- Not Qubes HVM: shared host kernel for NixOS zones only; ISO guests are full QEMU HVMs on the bunker LAN.
- Guest networking / audio / clipboard are whatever the guest OS provides.
- Voice/metadata NixOS toggles do not apply inside foreign ISOs (host `mat2` still available).
- **Mouse cursor** inside the ISO is controlled by that OS — bunker only colors the host launcher and QEMU window title (see [colors.md](colors.md)).

See also: [egress.md](egress.md), [usb.md](usb.md), [MANUAL.txt](MANUAL.txt).
