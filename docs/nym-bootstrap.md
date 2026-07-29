# Nym bootstrap on the net microVM
#
# SOCKS ports come from config/zones.nix (bound on 10.0.0.1).
# Default examples: personal 1081, work 1082, browse 1083, radio 1084.
# See /etc/bunker/nym-ports inside the net VM after build.
#
# Tor fallback: 127.0.0.1:9050 (optional bunker-tor-socks-fallback.service)

## First boot inside net VM

```bash
sudo -u nym -H bash
export HOME=/var/lib/nym
cd /var/lib/nym

# Init one client id per app zone name from config/zones.nix
for z in personal work browse radio; do
  mkdir -p "$z"
  cd "$z"
  nym-client init --id "$z" || true
  cd ..
done

sudo systemctl restart 'nym-socks-*'
sudo systemctl status 'nym-socks-*'
```

If `nym-client` CLI flags differ, run `nym-client --help` and adjust
`modules/guests/net.nix` ExecStart.

## Verify from an app VM

```bash
curl -x socks5h://10.0.0.1:1081 https://ifconfig.me
# without proxy / clearnet should fail if killswitch is on
```

## Temporary Tor-only path

```bash
sudo systemctl start bunker-tor-socks-fallback
```
