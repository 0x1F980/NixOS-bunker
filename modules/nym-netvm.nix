# netVM-related host policy (mixnet runs inside net microVM).
# SOCKS port list is generated from config/zones.nix onto the net guest;
# this file is host-side operator documentation.
{
  lib,
  bunkerAppZones ? import ../config/zones.nix,
  ...
}:

{
  services.tor.enable = false;

  environment.etc."bunker/nym-routing".text = ''
    Nym/Tor/i2pd run ONLY in the net microVM.
    SOCKS ports on netVM (10.0.0.1) — from config/zones.nix:
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: z:
        if z ? socks && z.socks != null then "  ${name} ${toString z.socks}" else "  ${name} (no socks)"
      ) bunkerAppZones
    )}
    App VMs must not run nym-client or change mixnet config.
    Killswitch: bunker-killswitch enable|disable|status
  '';
}
