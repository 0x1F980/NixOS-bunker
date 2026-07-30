# Emit zone registry onto the host (/etc/bunker/zones.json + .tsv).
# Invisible zones (invisible=true) stay in zones.json; GNOME hides until sflc unlock.
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
      let
        typ =
          if (z.kind or "") == "template" then
            "template"
          else if z.disposable or false || (z.kind or "") == "disposable" then
            "disposable"
          else
            "persistent";
        iso = z.iso or "";
      in
      lib.concatStringsSep "\t" [
        name
        z.template
        z.ip
        (if (z.socks or null) == null then "-" else toString z.socks)
        typ
        (z.color or "gray")
        (z.internet or "nym")
        (lib.concatStringsSep "," (z.usb or [ ]))
        (lib.concatStringsSep "," (z.apps or [ ]))
        iso
      ]
    ) bunkerPublicZones
  );
}
