# Portable hardening — all architectures.
{ lib, pkgs, ... }:

{
  networking.firewall = {
    enable = true;
    allowPing = false;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  boot.tmp.useTmpfs = true;
  boot.kernelParams = [
    "slab_nomerge"
    "page_alloc.shuffle=1"
    "random.trust_cpu=off"
  ];

  services.avahi.enable = false;
  services.printing.enable = false;
  services.openssh.enable = false;
  hardware.bluetooth.enable = false;

  programs.firejail.enable = true;

  systemd.coredump.enable = false;
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "core";
      type = "hard";
      value = "0";
    }
  ];
}
