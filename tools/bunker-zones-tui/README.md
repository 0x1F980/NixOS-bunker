# bunker-zones-tui

Ratatui CRUD for **AppVM · Disposable · Template · ISO/HVM** in `config/zones.json`.
Host launcher: **zones · service** (`bunker-zones`).

| Key | Action |
| --- | --- |
| `a` | Add **NixOS** zone |
| `A` / `I` | Add **ISO/HVM** zone (name → path wizard) |
| `n` | **Rename** zone |
| `c` | Cycle **color** (host icons + NixOS guest cursor after rebuild) |
| `k` | Cycle **kind**: appvm → disposable → template |
| `m` / `M` | **RAM** up / down (MiB steps) |
| `v` / `V` | **vCPU** up / down |
| `r` / `N` | Type exact RAM (MiB) / vCPU count |
| `t` / `o` / `b` | template / ISO path / boot |
| `i` | internet |
| `u` / `U` | USB add / pop |
| `p` / `P` | Apps (NixOS only) |
| `s` | Start selected |
| `w` | Save |

See [docs/colors.md](../../docs/colors.md), [docs/iso.md](../../docs/iso.md).
