# AppArmor — enforce where profiles exist.
{ lib, pkgs, ... }:

{
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = false;
  };

  # Enable common packages with AppArmor support when available
  security.apparmor.packages = [ pkgs.apparmor-profiles ];
}
