# Egress: Nym / i2p / Tor

netVM exposes **three** SOCKS backends per zone (see `/etc/bunker/egress-ports`):

| Backend | LAN port | Notes |
| --- | --- | --- |
| **nym** | `socks` (e.g. 1081) | **One** shared Nym identity (Nym limit) |
| **i2p** | `socks+1000` (e.g. 2081) | i2pd SOCKS outproxy — **alternative to Nym** |
| **tor** | `socks+2000` (e.g. 3081) | Tor SOCKS |

## Per zone

```bash
bunker-zone set personal internet=nym
bunker-zone set work internet=i2p
bunker-zone set browse internet=tor
bunker-zone set radio internet=none
sudo nixos-rebuild switch --flake .#host
```

`none` = LAN only (no mixnet proxy env).

## Bootstrap

- Nym: [nym-bootstrap.md](nym-bootstrap.md) (single `nym-client` id `bunker`)
- i2p: starts with netVM (`services.i2pd`); first connect may be slow while integrating
- Tor: always on as `tor.service` on netVM

USB attach defaults: [usb.md](usb.md). Portability: [portability.md](portability.md).
