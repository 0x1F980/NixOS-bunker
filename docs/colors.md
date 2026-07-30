# Zone colors (labels, icons, guest cursor)

Palette SoT: [`config/colors.nix`](../config/colors.nix) — `red` `orange` `yellow` `green` `blue` `purple` `black` `gray`.

Each zone has `"color": "<name>"` in `zones.json`.

## What color changes

| Surface | Effect |
| --- | --- |
| Host launchers | Colored SVG icon (`zones · service` / GNOME) |
| Deniable XDG icons | Colored SVG under `/run/bunker/xdg` when unlocked |
| NixOS guest shell | PS1 + `BUNKER_ZONE_*` env |
| **NixOS guest mouse** | XCursor theme `bunker-<color>` + `XCURSOR_THEME` / GTK settings |
| ISO/HVM | Host icon + QEMU window title `bunker:name[color]` — **guest OS owns its cursor** |

## CRUD

**zones · service** / **deniable · service**:

- `c` — cycle color (shows hex)
- `n` — rename zone

CLI:

```bash
bunker-zone set work color=blue
bunker-zone rename work work2
bunker-zone colors
```

After **color** or **rename** on NixOS zones:

```bash
sudo nixos-rebuild switch --flake .#host
bunker-zone-start <zone>
```

ISO zones: save JSON and restart the QEMU window; no guest cursor injection.

## Guest cursor (NixOS)

Built in [`modules/guests/zone-cursor.nix`](../modules/guests/zone-cursor.nix), wired from [`mk-app-zone.nix`](../modules/guests/mk-app-zone.nix):

- Theme name: `bunker-<color>`
- Env: `XCURSOR_THEME`, `XCURSOR_SIZE=24`
- GTK 3/4 `settings.ini` cursor theme

Ready for graphical apps / future Wayland-X sessions inside the zone.
