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
    ../../modules/clipboard-oneway.nix
    ../../modules/microvm-network.nix
    ../../modules/zones-registry.nix
    ../../modules/zones-ui.nix
    # Hardware overlays via flake mkHost (x86_64 / aarch64 / …)
  ];

  networking.hostName = "nixos-bunker";
  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [
    "interface-name:br-bunker"
    "interface-name:vm-*"
  ];
  networking.firewall.enable = true;
  # Operator SSH (hardening-portable disables it by default)
  services.openssh.enable = lib.mkForce true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = "no";
  networking.firewall.allowedTCPPorts = [ 22 ];

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
    pkg: builtins.elem (lib.getName pkg) [ "obsidian" ];

  system.stateVersion = "26.05";
}
