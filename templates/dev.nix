# Dev — desktop + editor/compiler (networked work zone).
# Offline math (Julia) lives in vault — air-gapped.
{ pkgs, ... }:

{
  imports = [ ./desktop.nix ];
  environment.systemPackages = with pkgs; [
    vscodium
    gcc
    git
  ];
}
