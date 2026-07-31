# Portable x86_64 overlay — Intel or AMD KVM (not Xen).
{ lib, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [
    "kvm-intel"
    "kvm-amd"
  ];
  virtualisation.libvirtd.enable = lib.mkDefault false;
}
