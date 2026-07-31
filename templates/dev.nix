# Dev — desktop + editor/compiler + Julia (math).
{ pkgs, ... }:

{
  imports = [ ./desktop.nix ];
  environment.systemPackages = with pkgs; [
    vscodium
    gcc
    git
    julia
  ];
}
