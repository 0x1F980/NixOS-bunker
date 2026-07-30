# NixOS-bunker

Hardened KVM/microVM workstation — **not Qubes**. Simplicity is the hardening.

**Repo:** https://github.com/0x1F980/NixOS-bunker

## Model

- **Zone** = one VM · **`apps[]`** catalog · **`mem`/`diskGb`** limits on the zone
- **`invisible`+`layer`** Shufflecake hide · **`panic`:** `keep`\|`lock`\|`wipe`
- **Brokers:** net / usb / voice · **UI:** `bunker` TUI only

## Use

```bash
sudo nixos-rebuild switch --flake .#host
bunker
bunker-zone-start net
bunker-zone-start personal
```

| Cmd | Role |
| --- | --- |
| `bunker` | operator TUI |
| `bunker-zone …` | CRUD `zones.json` |
| `bunker-sflc unlock <layer>` | invisible layer |
| `bunker-panic` | panic wipe/lock |

Passwords: `bunker`/`changeme-bunker`, `admin`/`changeme-admin` — [docs/ADMIN-RECOVER.md](docs/ADMIN-RECOVER.md).

Docs: [deniable](docs/deniable.md) · [egress](docs/egress.md) · [usb](docs/usb.md) · `man bunker`
