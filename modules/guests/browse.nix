# DEPRECATED — see config/zones.nix (template = "browser", disposable = true).
{ ... }:
{
  imports = [
    (import ./mk-app-zone.nix {
      name = "browse";
      zone = (import ../../config/zones.nix).browse;
    })
  ];
}
