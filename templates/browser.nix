# Browser disposable — LibreWolf + Tails' Metadata Cleaner (mat2 GUI).
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    librewolf
    bleachbit
    metadata-cleaner
    wl-clipboard
  ];
  systemd.coredump.enable = false;
}
