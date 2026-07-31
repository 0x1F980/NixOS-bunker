# NixOS-bunker — user guide

Operator guide for cautious daily use. Host = admin only. Work in zones.

---

## 1. First boot / install checklist

1. On the machine: generate real hardware config  
   `sudo nixos-generate-config --show-hardware-config > hosts/bunker/hardware-configuration.nix`
2. Unlock host WAN briefly, rebuild, lock again:

```bash
sudo bunker-host-net allow
cd ~/NixOS-bunker   # or your clone path
sudo nixos-rebuild switch --flake .#host-x86_64-linux   # or aarch64 / riscv64
sudo bunker-host-net lock
```

3. Once: Shufflecake image + layer passphrases  

```bash
sudo bunker-sflc bootstrap
```

4. Change default passwords (`bunker`, `admin`/`root`, zone user) — see [ADMIN-RECOVER.md](ADMIN-RECOVER.md).  
5. Start brokers, then apps — **in TUI**: `s` → `net`, `s` → `usb`, `s` → zone  
   (or CLI `bunker-zone-start …`)

Shufflecake once: TUI **`b`**. Host updates: TUI **`h`** → allow/lock.
---

## 2. Daily rules

| Do | Don’t |
| --- | --- |
| Browse/mail/dev **in zones** | Browse on the **host** |
| Keep `bunker-host-net` **locked** | Leave host WAN open after updates |
| Use `bunker-file` / `bunker-clip` | Mount guest disks on host |
| USB via `bunker-usb-attach` | Plug sensitive USB into host for apps |
| Start **net** before app zones | Expect clearnet without SOCKS |

---

## 3. Ratatui (`bunker`) — alt til den ikke-tekniske bruger

```
s start     v usb       h host-net    b sflc-bootstrap
a add       d del       r rename      c color     t type
n net       i hide      u unlock      o iso       f file copy
Space panic (keep|lock|wipe)          p ARM       w save      q quit
```

| Behov | Tast |
| --- | --- |
| Start netVM / usbVM / zone / all | `s` → `net` / `usb` / `all` / zonenavn |
| USB til valgt zone (via usbVM) | `v` → `vid:pid` (`-vid:pid` = detach) |
| Host WAN til updates | `h` → `a` allow / `l` lock / `t` status |
| Shufflecake første gang | `b` → passphrase pr. lag |
| Net-backend pr. zone (via netVM) | `n` |
| Flyt fil mellem VMs | `f` |
| Hide / unlock | `i` / `u` |

Brokers: **netVM** og **usbVM** er **1→many**. Fil-copy er zone↔zone via host.

- **`w`** gemmer `zones.json`.  
- Efter store politik-ændringer: `h`→allow → rebuild i terminal → `h`→lock → `s` start zone.
---

## 4. Networking

- Guests have **no default gateway**. Traffic is **SOCKS-only** via netVM.  
- Per zone: `internet` = `nym` | `i2p` | `tor` | `none` (TUI `n`).  
- DNS for guests: Tor DNSPort on `10.0.0.1`.  
- Details: [egress.md](egress.md).

**Updates on host:**

```bash
sudo bunker-host-net allow
sudo nixos-rebuild switch --flake .#host-x86_64-linux
sudo bunker-host-net lock
```

---

## 5. Clipboard & files

```bash
bunker-clip send personal
bunker-clip copy work personal
bunker-file copy personal:/home/zone/a.pdf work:/home/zone/a.pdf
# TUI: f → srcZone:/path dstZone:/path
```

See [file-copy.md](file-copy.md).

---

## 6. USB

```bash
bunker-usb-attach <zone> 0bda:2838
bunker-usb-detach <zone> 0bda:2838
```

Devices attach to **usbVM**, then to the zone. See [usb.md](usb.md).

---

## 7. Invisible zones (Shufflecake)

Hidden zone **names** are not in public config. Unlock a layer → they appear in TUI → start them. Lock → they vanish.

```bash
# First time: sudo bunker-sflc bootstrap  (optionally create a hidden zone into the layer)
# Daily:
#   TUI u → layer # → passphrase   → hidden zones show up
#   TUI i (after unlock) → assign free slot → w save
#   TUI s to start · bunker-term <name>
sudo bunker-sflc lock all
bunker-sflc status
```

See [deniable.md](deniable.md).

---

## Panic

TUI: `Space` cycles `keep` | `lock` | `wipe` per zone → `w` → rebuild.  
Arm: TUI `p` + code, or `bunker-panic`.

| Mode | Effect |
| --- | --- |
| keep | leave zone data |
| lock | **stop** those zone VMs |
| wipe | shred zone disks |

Then: lock all Shufflecake layers + best-effort RAM wipe.
---

## 9. ISO / HVM zones

TUI `o` → path to ISO, or `template=iso` + `iso=/path`.  
Runs via QEMU (KVM native or TCG). Foreign arch: `BUNKER_ISO_ARCH=…`.

---

## 10. Useful commands

| Command | Purpose |
| --- | --- |
| `bunker` | Operator TUI |
| `bunker-zone …` | CLI CRUD |
| `bunker-zone-start <z\|all>` | Start microVM / ISO |
| `bunker-term <z>` | Colored SSH into zone |
| `bunker-host-net status` | Host clearnet lock state |
| `bunker-killswitch status` | Guest WAN killswitch |
| `bunker-wipe <z>` | Wipe disposable data |
| `bunker-test-isolation` | Smoke checks |
| `bunker-help` / `man bunker` | Short manual |

---

## 11. Default accounts (change these)

See [ADMIN-RECOVER.md](ADMIN-RECOVER.md). Zone user is typically `zone` / `zone` until you harden SSH keys.
