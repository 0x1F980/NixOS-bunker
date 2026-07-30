# Login / SSH recover

## Passwords (after flake switch)

| Bruger | Kode |
| --- | --- |
| `bunker` | `changeme-bunker` |
| `admin` | `changeme-admin` |
| `root` | `changeme-admin` |

## Diagnose SSH (kør ALT)

```bash
# 1) Er OpenSSH overhovedet i den aktive generation?
nixos-option services.openssh.enable
nixos-option services.openssh.startWhenNeeded

# 2) Hvilke SSH-units findes? (klassisk fælde: kun socket)
systemctl list-unit-files '*ssh*'
systemctl list-units --all '*ssh*'
systemctl status sshd.socket || true
systemctl status sshd.service || true

# 3) Lytter noget på 22?
ss -lptn | grep ':22' || true
```

**Hvis `sshd.socket` er active/listening:** SSH virker allerede — `sshd.service` mangler med vilje (socket activation). Test: `ssh bunker@127.0.0.1`.

**Hvis INGEN ssh-units:** flake-switch landede ikke. Se nedenfor.

## Fix / rebuild

```bash
cd ~/NixOS-bunker
git fetch origin && git reset --hard origin/master
sudo nixos-rebuild switch --flake .#host
systemctl start sshd
systemctl status sshd
```

Login: `ssh bunker@IP` — `changeme-bunker`.
