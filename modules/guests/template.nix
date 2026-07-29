# Shared app template — Qubes-like universal packages for app VMs.
{ pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    keepassxc
    pass
    gnupg
    kdePackages.kleopatra
    nitrokey-app
    age
    bleachbit
    thunderbird
    neomutt
    element-desktop
    librewolf
    obsidian
    zotero
    kiwix
    libreoffice
    stellarium
    kdePackages.marble
    btop
    glances
    zellij
    borgbackup
    restic
    git
    firejail
    bubblewrap
    wl-clipboard
  ];

  programs.firejail.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
  };

  # DNS must come from netVM — do not use public resolvers
  networking.nameservers = lib.mkDefault [ "10.0.0.1" ]; # netVM DNS — adjust to your microvm net
  services.timesyncd.enable = false; # NTP via netVM only when configured
}
