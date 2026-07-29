# DEPRECATED — zone definitions live in config/zones.nix (template = "desktop").
# Kept only so old docs/paths do not 404; flake no longer imports this file.
{ ... }:
{
  imports = [
    (import ./mk-app-zone.nix {
      name = "personal";
      zone = (import ../../config/zones.nix).personal;
    })
  ];
}
