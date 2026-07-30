# Dev — desktop + editor/compiler.
{ pkgs, ... }:

{
  imports = [ ./desktop.nix ];
  environment.systemPackages = with pkgs; [
    vscodium
    gcc
    git
  ];
}
