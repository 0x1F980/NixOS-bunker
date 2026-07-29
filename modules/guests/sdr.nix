# DEPRECATED — zone renamed to "radio" in config/zones.nix (template = "radio").
{ ... }:
{
  imports = [
    (import ./mk-app-zone.nix {
      name = "radio";
      zone = (import ../../config/zones.nix).radio;
    })
  ];
}
