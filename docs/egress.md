# Egress via netVM — SOCKS only (no guest NAT)

netVM (`10.0.0.1`) is a **proxy broker**, not a router for guests.

## Hard rules

1. **`ip_forward=0`** on netVM — no guest→WAN forwarding  
2. **No MASQUERADE** of `10.0.0.0/24`  
3. **FORWARD DROP**  
4. Guests have **no default gateway** — clearnet has nowhere to go  
5. Guest OUTPUT firewall: only this zone’s SOCKS port + DNS `:53` on netVM + usbVM  
6. Guest DNS = **Tor DNSPort** on `10.0.0.1:53` (not clearnet unbound)

Apps that ignore `ALL_PROXY` **fail closed**.

## SOCKS ports

| Backend | Port | Notes |
| --- | --- | --- |
| nym | `socks` | shared Nym identity |
| i2p | `socks+1000` | i2pd |
| tor | `socks+2000` | Tor |

```bash
bunker-zone set personal internet=tor   # or nym|i2p|none
# TUI: n
sudo nixos-rebuild switch --flake .#host-x86_64-linux
```

`none` = bunker LAN only (still no WAN).

Local daemons on netVM (tor/i2pd/nym) may use WAN on eth1; guests may not.
