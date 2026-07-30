# Login / SSH recover

## Passwords (after this flake switch)

| Bruger | Kode |
| --- | --- |
| `bunker` | `changeme-bunker` |
| `admin` | `changeme-admin` |
| `root` | `changeme-admin` |

Skift bagefter: `passwd`.

## SSH (`sshd.service`)

Flake host **enabler** OpenSSH. Efter switch skal unit findes:

```bash
cd /path/to/NixOS-bunker
sudo nixos-rebuild switch --flake .#host
systemctl status sshd
ss -lptn | grep ':22'
```

Login udefra:

```bash
ssh bunker@10.118.58.245
# password: changeme-bunker
```

## Hvis du er låst ude

1. Boot ældre NixOS-generation  
2. `git pull` i repoet  
3. `sudo nixos-rebuild switch --flake .#host`
