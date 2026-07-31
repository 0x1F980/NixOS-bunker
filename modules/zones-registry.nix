# Zone registry on host (/etc/bunker/zones.json + slots + .tsv).
# Public zones only — hidden names live in Shufflecake layerN/hidden-zones.json.
{
  lib,
  pkgs,
  bunkerPublicZones ? import ../config/zones.nix,
  ...
}:

{
  environment.etc."bunker/zones.json".source = ../config/zones.json;
  environment.etc."bunker/slots.json".source = ../config/slots.json;

  # Mutable runtime SoT — TUI/CLI edit this; seed once from etc.
  # Ensure net/usb broker entries exist (kind/disposable editable in TUI).
  system.activationScripts.bunkerZonesMutable.text = ''
    mkdir -p /var/lib/bunker
    chmod 0750 /var/lib/bunker
    if [ ! -f /var/lib/bunker/zones.json ]; then
      cp /etc/bunker/zones.json /var/lib/bunker/zones.json
      chmod 0640 /var/lib/bunker/zones.json
    else
      ${pkgs.python3}/bin/python3 - <<'PY'
import json
from pathlib import Path
mut = Path("/var/lib/bunker/zones.json")
etc = Path("/etc/bunker/zones.json")
z = json.loads(mut.read_text())
e = json.loads(etc.read_text())
changed = False
for name in ("net", "usb"):
    if name not in z and name in e:
        z[name] = e[name]
        changed = True
    elif name in z:
        z[name].setdefault("role", "broker")
        changed = True
if changed:
    mut.write_text(json.dumps(z, indent=2) + "\n")
PY
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
        (z.template or name)
        (z.ip or "-")
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
