# Zone registry on host (/etc/bunker/zones.json + slots + .tsv).
# Public zones only — hidden names live in Shufflecake layerN/hidden-zones.json.
{
  lib,
  bunkerPublicZones ? import ../config/zones.nix,
  ...
}:

{
  environment.etc."bunker/zones.json".source = ../config/zones.json;
  environment.etc."bunker/slots.json".source = ../config/slots.json;

  # Mutable runtime SoT — TUI/CLI edit this; seed once from etc.
  system.activationScripts.bunkerZonesMutable.text = ''
    mkdir -p /var/lib/bunker
    chmod 0750 /var/lib/bunker
    if [ ! -f /var/lib/bunker/zones.json ]; then
      cp /etc/bunker/zones.json /var/lib/bunker/zones.json
      chmod 0640 /var/lib/bunker/zones.json
    fi
  '';

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
