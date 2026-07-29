# Clipboard policy — mediated only; TTL and paths are operator-hackable.
# Override TTL: set BUNKER_CLIP_TTL in the environment, or edit /etc/bunker/clipboard.conf
# (this module ships the default conf; users can replace via configuration.nix).
{ lib, ... }:

{
  # No SPICE/QEMU guest↔host clipboard on microVMs (see microvm-base).
  environment.etc."bunker/clipboard.conf".text = ''
    # Seconds until ZONE clipboard is wiped after bunker-clip send|copy.
    # Host/global clipboard is NEVER auto-cleared by send|copy.
    # Override at runtime: BUNKER_CLIP_TTL=60 bunker-clip send personal
    TTL=30
  '';

  environment.etc."bunker/clipboard-policy".text = ''
    ALLOWED
      bunker-clip send <zone>        host clipboard → zone (host/global KEPT)
      bunker-clip copy <src> <dst>   zone → zone via host staging only
      bunker-clip clear              wipe staging + host clipboard NOW (manual)

    BLOCKED (no supported path)
      guest → host clipboard
      SPICE / QEMU shared clipboard
      automatic VM↔VM clipboard
      vault (no NIC) — use USB/volume instead

    AUTO-CLEAR
      After send|copy: destination ZONE clipboard clears after TTL seconds
        (default 30; /etc/bunker/clipboard.conf or BUNKER_CLIP_TTL).
      Host/global clipboard is kept on send|copy (your normal copy stays).
  '';

  # Default for shells that inherit it; conf file still wins when env unset
  environment.variables.BUNKER_CLIP_TTL = lib.mkDefault "30";
}
