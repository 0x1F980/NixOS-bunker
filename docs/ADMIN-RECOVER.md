# Locked out of GDM / wrong password

## Right now (GDM accepterer ikke koden)

`anon` findes **ikke** efter bunker-switch. Brug kun:

| Bruger | Kode |
| --- | --- |
| `bunker` | `changeme-bunker` |
| `admin` | `changeme-admin` |

Hvis det stadig fejler (`initialPassword` var upålidelig — fixed med `hashedPassword`):

### A — Forrige generation (hurtigst)

1. Genstart  
2. I **systemd-boot**: vælg en **ældre** NixOS-generation (før bunker)  
3. Log ind som `anon` med dit gamle kodeord  
4. Så:
   ```bash
   cd ~/nixos-bunker
   git pull
   sudo nixos-rebuild switch --flake .#host
   ```
5. Log ind som **`bunker` / `changeme-bunker`**

### B — TTY

Ctrl+Alt+F3 → `admin` / `changeme-admin` (eller `bunker`).  
Virker TTY men ikke GDM = session-problem, ikke kode.

### C — Live ISO / nixos-enter

Se tidligere: mount LUKS, `nixos-enter`, sæt `hashedPassword` eller `passwd` efter midlertidig `mutableUsers`.

## Efter unlock

```bash
passwd   # som bunker / admin — skift defaults
```

`bunker` har **ikke** wheel (med vilje). Rebuild = `admin`.
