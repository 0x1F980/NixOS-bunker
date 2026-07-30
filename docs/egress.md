# Egress via netVM

netVM (`10.0.0.1`) fronts SOCKS per zone:

| Backend | Port | Notes |
| --- | --- | --- |
| nym | `socks` | shared Nym identity |
| i2p | `socks+1000` | i2pd |
| tor | `socks+2000` | Tor |

```bash
bunker-zone set personal internet=nym   # or i2p|tor|none
# or in bunker TUI: n
sudo nixos-rebuild switch --flake .#host
```

`none` = bunker LAN only.
