# Zone registry on host (/etc/bunker/zones.json + .tsv).
{
  lib,
  bunkerPublicZones ? import ../config/zones.nix,
  ...
}:

{
  environment.etc."bunker/zones.json".source = ../config/zones.json;

  environment.etc."bunker/zones.tsv".text = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: z:
      let
        typ =
          if (z.kind or "") == "template" then
            "template"
          else if z.disposable or false || (z.kind or "") == "disposable" then
            "disposable"
          else
            "persistent";
      in
      lib.concatStringsSep "\t" [
        name
        z.template
        z.ip
        (if (z.socks or null) == null then "-" else toString z.socks)
        typ
        (z.color or "gray")
        (z.internet or "tor")
        (lib.concatStringsSep "," (z.usb or [ ]))
        (lib.concatStringsSep "," (z.apps or [ ]))
      ]
    ) bunkerPublicZones
  );
}
