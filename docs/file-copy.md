# Mediated file copy (Qubes-like)

Full file/directory transfer between zones via the host. Staging is shredded after transfer. No guest filesystem mount on the host.

## Commands

```bash
bunker-file copy personal:/home/zone/doc.pdf work:/home/zone/inbox/doc.pdf
bunker-file put  work ./report.pdf /home/zone/report.pdf
bunker-file get  browse /home/zone/out.bin ./out.bin
```

TUI: `f` → `srcZone:/path dstZone:/path`

## Also

Clipboard remains `bunker-clip` (text). File copy is separate and intentional.
