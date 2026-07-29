# Login broken / locked out

## Hvis GDM afviser bunker/admin

Den generation der kører nu har **tomme/låste** passwords (`initialPassword`-bug).
Nye koder virker **først efter** `git pull` + `switch` fra en generation du *kan* bruge.

### 1) Boot forrige generation (gør det nu)

1. Genstart  
2. systemd-boot-menu → **ældre NixOS** (før bunker / hvor `anon` findes)  
3. Log ind som **`anon`** (dit gamle kodeord)

### 2) Aktivér login-fix

```bash
cd ~/nixos-bunker
git pull
sudo nixos-rebuild switch --flake .#host
```

### 3) Log ind (efter switch)

| Hvor | Bruger | Kode |
| --- | --- | --- |
| GDM | `bunker` | `bunker` |
| GDM | `admin` | `admin` |
| Ctrl+Alt+F2 | `root` | `admin` |
| TTY1 | `admin` | **autologin** (ingen kode) |

Skift bagefter: `passwd` — og fjern root-hash + `services.getty.autologinUser` i `modules/host-minimal.nix`.

### Uden git (manuel)

Som `anon` på gammel generation, ret `~/nixos-bunker/modules/host-minimal.nix`:
sæt `hashedPassword` for bunker/admin (se git `623fcb0` / nyere), så `sudo nixos-rebuild switch --flake .#host`.
