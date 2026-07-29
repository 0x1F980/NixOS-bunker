# Nym bootstrap on the net microVM
#
# IMPORTANT: Nym allows only ONE mixnet identity at a time.
# This bunker runs a single `nym-client` (id=bunker). Zone ports 1081+ are
# just local SOCKS frontends to that one client — zones SHARE the Nym identity.
#
# Tor fallback: systemctl start bunker-tor-socks-fallback

## First boot inside net VM

```bash
sudo -u nym -H bash
export HOME=/var/lib/nym
mkdir -p /var/lib/nym/bunker
cd /var/lib/nym/bunker
nym-client init --id bunker || true

sudo systemctl restart nym-client
sudo systemctl restart 'nym-socks-*'
sudo systemctl status nym-client 'nym-socks-*'
```

## Verify from an app VM

```bash
curl -x socks5h://10.0.0.1:1081 https://ifconfig.me
# without proxy / clearnet should fail if killswitch is on
```

## Temporary Tor-only path

```bash
sudo systemctl start bunker-tor-socks-fallback
```
