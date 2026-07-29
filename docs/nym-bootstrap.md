# Nym bootstrap (optional — or use i2p/Tor, see docs/egress.md)
#
# Nym allows only ONE mixnet identity. This bunker uses id `bunker`.
# Prefer i2p if you do not want Nym: bunker-zone set <z> internet=i2p

## First boot inside net VM

```bash
sudo -u nym -H bash
export HOME=/var/lib/nym
mkdir -p /var/lib/nym/bunker && cd /var/lib/nym/bunker
nym-client init --id bunker || true
sudo systemctl restart nym-client 'nym-socks-*'
```

## Verify

```bash
# nym (default ports)
curl -x socks5h://10.0.0.1:1081 https://ifconfig.me
# i2p alternative
curl -x socks5h://10.0.0.1:2081 https://example.com
# tor
curl -x socks5h://10.0.0.1:3081 https://example.com
```

Full matrix: [docs/egress.md](egress.md)
