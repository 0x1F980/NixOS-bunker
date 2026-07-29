# Nym bootstrap on the net microVM
#
# SOCKS ports (bind on 10.0.0.1):
#   personal 1081
#   work     1082
#   browse   1083
#   sdr      1084
#
# Tor fallback: 127.0.0.1:9050 (and optional bunker-tor-socks-fallback.service)

## First boot inside net VM

```bash
# as root or nym user
sudo -u nym -H bash
export HOME=/var/lib/nym
cd /var/lib/nym

for z in personal work browse sdr; do
  mkdir -p "$z"
  cd "$z"
  nym-client init --id "$z" || true
  cd ..
done

sudo systemctl restart nym-socks-personal nym-socks-work nym-socks-browse nym-socks-sdr
sudo systemctl status 'nym-socks-*'
```

If `nym-client` CLI flags differ on your nixpkgs version, run `nym-client --help` and adjust
`modules/guests/net.nix` ExecStart accordingly.

## Verify from an app VM

```bash
# inside personal (10.0.0.11)
curl -x socks5h://10.0.0.1:1081 https://ifconfig.me
# without proxy / clearnet should fail if host killswitch + no guest NAT
```

## Temporary Tor-only path

```bash
# on netVM
sudo systemctl start bunker-tor-socks-fallback
```
