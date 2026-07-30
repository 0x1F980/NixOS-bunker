# Daily apps — small set, durable.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    librewolf
    keepassxc
    pass
    gnupg
    age
    git
    btop
    wl-clipboard
    bleachbit
  ];
  systemd.coredump.enable = false;
}
