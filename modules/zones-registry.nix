# Emit zone registry onto the host for operator scripts.
{
  lib,
  bunkerAppZones ? import ../config/zones.nix,
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
        (z.internet or "proxy")
        (lib.concatStringsSep "," (z.usb or [ ]))
        (lib.concatStringsSep "," (z.apps or [ ]))
      ]
    ) bunkerAppZones
  );
}
