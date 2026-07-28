# Admin lockout recover

If `admin` is locked out or a bad generation breaks the host:

1. **Previous generation** — at systemd-boot menu, pick an older NixOS generation.
2. **Live ISO** — boot NixOS installer, mount LUKS/root, then:
   ```bash
   nixos-enter
   passwd admin
   # or edit /etc/nixos / flake and:
   nixos-rebuild switch --flake /path/to/nixos-bunker#host
   ```
3. **Do not** use `admin` for daily GNOME — keep it for TTY/`nixos-rebuild` only.
4. Keep `bunker` without `wheel` so a compromised daily session cannot rebuild the host.
