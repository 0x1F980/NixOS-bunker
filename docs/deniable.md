# Skjulte zoner (Shufflecake) — til dig der bare vil bruge det

Hemmelige VM-navne og deres diske bor **kun** inde i et Shufflecake-lag.  
Public config (`zones.json`) må **aldrig** kende dem.

**Vigtigt:** Det er **ikke** magi i config. Det virker kun hvis **du** bruger det rigtigt. Forkert brug = ingen plausible deniability.

## Du skal gøre dette (ellers er det ikke skjult)

1. **Bootstrap én gang** — TUI `b` eller `sudo bunker-sflc bootstrap`  
   Vælg **egne** lag-passphrases. Gem dem **ikke** i git, chat, notes på hosten eller denne repo.
2. **Opret hemmelig zone kun efter unlock** — TUI `u` → lag → passphrase → `i` (hide) på en zone → `w`  
   Eller svar “ja” ved bootstrap og giv et **nyt** navn (kun dig kender det).
3. **Aldrig** skriv hemmelige zonenavne i:
   - `config/zones.json` / `/var/lib/bunker/zones.json` (public)
   - README, commits, issues, Discord
   - filer i `~/nixos-bunker` der synces/backes op
4. **Lås når du er færdig** — `sudo bunker-sflc lock all`  
   Så forsvinder navnene fra TUI. Uden passphrase kan zonen ikke startes.
5. **Repo på disken:** hvis du beholder git-checkout i home, kan templates (fx SDR-pakker) stadig ses. Det er **kapacitet**, ikke dit hemmelige navn — men slet/flyt repo hvis du vil mindske spor.

## Daglig brug

| Handling | TUI / kommando |
| --- | --- |
| Lås op | `u` → lagnummer → passphrase |
| Skjul en zone | efter unlock: `i` → `w` |
| Start | `s` (kører anonym slot `d1`… bagved) |
| Terminal ind | `e` |
| Lås | `bunker-sflc lock all` |

## Model (kort)

| Altid synligt (public) | Kun efter unlock |
| --- | --- |
| `personal` / `work` / `browse` / `vault` | Dit hemmelige **radio**-navn i `layerN/hidden-zones.json` |
| Ét anonymt slot `d1` (template **radio** only) | Disk + navn mapped til `d1` |

**Policy:** Kun **radio** er deniable. Ingen deniable desktop/vault-slots.

Eksempel efter unlock: hemmeligt navn → slot `d1` (radio; kun dig kender navnet).

## Hvad det IKKE lover (honesty)

Selv ved korrekt brug kan en tekniker se:

- at Shufflecake / `dm_sflc` findes
- at der findes anonym slot `d1` (radio-kapacitet) i systemet
- git/templates (inkl. `templates/radio.nix`) hvis repo ligger i home

Det lover **ikke** “denne maskine har aldrig haft skjulte VM’er”.  
Det lover: **uden din lag-passphrase findes dit hemmelige zonenavn og dens data ikke i klartekst.**

Se også `man bunker` og [ADMIN-RECOVER.md](ADMIN-RECOVER.md) (login-passwords ≠ SFLC-passphrases).
