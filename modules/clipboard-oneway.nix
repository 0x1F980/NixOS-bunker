# Clipboard policy — minimal, explicit, mediated only.
{ ... }:

{
  # No SPICE/QEMU guest↔host clipboard on microVMs (see microvm-base).
  environment.etc."bunker/clipboard-policy".text = ''
    ALLOWED
      bunker-clip send <zone>        host clipboard → zone
      bunker-clip copy <src> <dst>   zone → zone via host /tmp only (not left on host clip)
      bunker-clip clear              wipe staging + host clipboard now

    BLOCKED (no supported path)
      guest → host clipboard
      SPICE / QEMU shared clipboard
      automatic VM↔VM clipboard
      vault (no NIC) — use USB/volume instead

    AUTO-CLEAR
      Staging files wiped after BUNKER_CLIP_TTL seconds (default 45).
      After "send", host clipboard is also cleared when the timer fires.
      Override: BUNKER_CLIP_TTL=120 bunker-clip send personal
  '';
}
