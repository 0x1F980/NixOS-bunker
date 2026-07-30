# Login / SSH recover

| User | Password |
| --- | --- |
| `bunker` | `changeme-bunker` |
| `admin` / `root` | `changeme-admin` |

```bash
cd ~/NixOS-bunker
sudo nixos-rebuild switch --flake .#host
systemctl start sshd
systemctl status sshd
ss -lptn | grep ':22'
```

If only `sshd.socket` exists, SSH still works via socket activation. If no ssh units: rebuild did not land — fix flake, switch again, boot previous generation if needed.
