# Host configuration — minimal "dom0-like" NixOS + microVM orchestration.
{
  config,
  lib,
  pkgs,
  self,
  ...
}:

{
  imports = [
    ../../modules/host-minimal.nix
    ../../modules/hardening-portable.nix
    ../../modules/hardening-apparmor.nix
    ../../modules/hardening-sysctl.nix
    ../../modules/hardening-storage.nix
    ../../modules/hardening-media.nix
    ../../modules/clipboard-oneway.nix
    ../../modules/voice-anon.nix
    ../../modules/nym-netvm.nix
    ../../modules/microvm-network.nix
    # Uncomment ONE hardware overlay as needed:
    # ../../hardware/generic-x86_64.nix
    # ../../hardware/aarch64-generic.nix
    # ../../hardware/mba52.nix
  ];

  networking.hostName = "nixos-bunker";
  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [
    "interface-name:br-bunker"
    "interface-name:vm-*"
  ];
  networking.firewall.enable = true;

  time.timeZone = "Europe/Copenhagen";
  i18n.defaultLocale = "da_DK.UTF-8";

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "admin"
    ];
  };

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "obsidian"
    ];

  system.stateVersion = "26.05";
}
