# Template: desktop — daily apps (Qubes-like TemplateVM package set)
# Arch-portable: skip packages that are x86-only / missing on aarch64.
{ pkgs, lib, ... }:

{
  environment.systemPackages =
    with pkgs;
    [
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
    ]
    # Obsidian binary is x86_64-only in nixpkgs today
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ obsidian ];

  programs.firejail.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
  };

  networking.nameservers = lib.mkDefault [ "10.0.0.1" ];
  services.timesyncd.enable = false;
}
