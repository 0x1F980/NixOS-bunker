# Host — thin shell + microVM orchestration.
{ lib, ... }:

{
  imports = [
    ../../modules/host-minimal.nix
    ../../modules/hardening.nix
    ../../modules/host-net-lock.nix
    ../../modules/clipboard-oneway.nix
    ../../modules/iso-qemu.nix
    ../../modules/microvm-network.nix
    ../../modules/zones-registry.nix
    ../../modules/zones-ui.nix
    ../../modules/shufflecake-deniable.nix
  ];

  networking.hostName = "nixos-bunker";
  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [
    "interface-name:br-bunker"
    "interface-name:vm-*"
  ];
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = lib.mkAfter [ 22 ];

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

  system.stateVersion = "26.05";
}
