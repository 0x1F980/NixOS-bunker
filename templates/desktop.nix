# Template: desktop — daily apps (Qubes-like TemplateVM package set)
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

  networking.nameservers = lib.mkDefault [ "10.0.0.1" ];
  services.timesyncd.enable = false;
}
