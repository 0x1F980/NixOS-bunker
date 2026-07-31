# Egress via netVM — SOCKS only (no guest NAT)

netVM (`10.0.0.1`) is a **proxy broker**, not a router for guests.

## Hard rules

1. **`ip_forward=0`** on netVM — no guest→WAN forwarding  
2. **No MASQUERADE** of `10.0.0.0/24`  
3. **FORWARD DROP**  
4. Guests have **no default gateway** — clearnet has nowhere to go  
5. Guest OUTPUT firewall: only this zone’s SOCKS port + DNS `:53` on netVM + usbVM  
6. Guest DNS = **Tor DNSPort** on `10.0.0.1:53` (or `socks5h` via cascade SOCKS)

Apps that ignore `ALL_PROXY` **fail closed**.

## SOCKS backends

Naming for cascades: **`inner-outer`** = guest talks to **outer**, which tunnels via **inner**.

| Backend | Port | Meaning |
| --- | --- | --- |
| nym | `socks` | Nym only |
| i2p | `socks+1000` | I2P only |
| tor | `socks+2000` | Tor only |
| nym-tor | `socks+3000` | Tor-over-Nym |
| i2p-tor | `socks+4000` | Tor-over-I2P |
| tor-nym | `socks+5000` | Nym-over-Tor |
| i2p-nym | `socks+6000` | Nym-over-I2P |
| none | — | LAN only |

```bash
bunker-zone set personal internet=i2p-tor
# TUI: n   cycles all backends
sudo nixos-rebuild switch --flake .#host-x86_64-linux
```

### Why not every pair?

**Supported 2-mixes** use a daemon that can take a SOCKS upstream (Tor `Socks5Proxy`, or a dedicated Nym client with `ALL_PROXY`).

**Not supported:** `nym-i2p` / `tor-i2p` (I2P **as outer** with Nym/Tor as transport). i2pd does not cleanly dial its garlic/NTCP links through an arbitrary SOCKS upstream; faking it with a local proxy chain breaks on `127.0.0.1` hops. Use `i2p` alone, or Tor-over-I2P (`i2p-tor`).

No 3+ hop chains (latency/failure without clear extra threat-model gain under SOCKS-only egress).

Local daemons on netVM may use WAN on eth1; guests may not.
