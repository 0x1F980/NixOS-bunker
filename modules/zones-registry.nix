# Emit public zone registry onto the host (/etc/bunker/zones.json + .tsv).
# Deniable whole-VMs live in deniable-zones.json (not listed here when locked).
# Egress backends: see docs/egress.md (Nym/i2p/Tor run in netVM only).
{
  lib,
  bunkerPublicZones ? import ../config/zones.nix,
  bunkerAppZones ? bunkerPublicZones,
  ...
}:

{
  environment.etc."bunker/zones.json".source = ../config/zones.json;

  environment.etc."bunker/zones.tsv".text = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: z:
      lib.concatStringsSep "\t" [
        name
        z.template
        z.ip
        (if (z.socks or null) == null then "-" else toString z.socks)
        (if z.disposable or false then "disposable" else "persistent")
        (z.color or "gray")
        (z.internet or "nym")
        (lib.concatStringsSep "," (z.usb or [ ]))
        (lib.concatStringsSep "," (z.apps or [ ]))
      ]
    ) bunkerPublicZones
  );
}
