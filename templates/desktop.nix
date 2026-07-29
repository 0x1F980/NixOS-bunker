# Template: desktop — daily apps (Qubes-like TemplateVM package set)
# Arch-portable: skip packages missing / x86-only on aarch64 & riscv64.
{ pkgs, lib, ... }:

let
  maybe =
    name:
    if builtins.hasAttr name pkgs then [ pkgs.${name} ] else [ ];
  # Heavy GUI / binary-only stuff: prefer when available
  maybePkg = p: lib.optional (p != null) p;
in
{
  environment.systemPackages =
    [
      pkgs.keepassxc
      pkgs.pass
      pkgs.gnupg
      pkgs.age
      pkgs.bleachbit
      pkgs.neomutt
      pkgs.btop
      pkgs.git
      pkgs.firejail
      pkgs.bubblewrap
      pkgs.wl-clipboard
      pkgs.borgbackup
      pkgs.restic
      pkgs.zellij
    ]
    ++ maybe "glances"
    ++ maybe "thunderbird"
    ++ maybe "element-desktop"
    ++ maybe "librewolf"
    ++ maybe "zotero"
    ++ maybe "kiwix"
    ++ maybe "libreoffice"
    ++ maybe "stellarium"
    ++ maybe "nitrokey-app"
    ++ lib.optionals (pkgs ? kdePackages) (
      maybePkg (pkgs.kdePackages.kleopatra or null)
      ++ maybePkg (pkgs.kdePackages.marble or null)
    )
    # Obsidian: x86_64-only binary in nixpkgs
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 (maybe "obsidian");

  programs.firejail.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
  };

  networking.nameservers = lib.mkDefault [ "10.0.0.1" ];
  services.timesyncd.enable = false;
}
