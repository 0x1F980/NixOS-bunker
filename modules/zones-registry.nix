# Emit zone registry onto the host for operator scripts.
{
  lib,
  bunkerAppZones ? import ../config/zones.nix,
  ...
}:

{
  environment.etc."bunker/zones.json".text = builtins.toJSON bunkerAppZones;

  environment.etc."bunker/zones.tsv".text = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: z:
      lib.concatStringsSep "\t" [
        name
        z.template
        z.ip
        (if z.socks == null then "-" else toString z.socks)
        (if z.disposable then "disposable" else "persistent")
      ]
    ) bunkerAppZones
  );
}
