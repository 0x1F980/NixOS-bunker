# DEPRECATED — see config/zones.nix (template = "dev").
{ ... }:
{
  imports = [
    (import ./mk-app-zone.nix {
      name = "work";
      zone = (import ../../config/zones.nix).work;
    })
  ];
}
