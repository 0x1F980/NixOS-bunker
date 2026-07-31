# Portable riscv64 overlay — KVM when hardware has H-extension; else TCG guests/ISO.
{ lib, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "riscv64-linux";
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "kvm" ];
  virtualisation.libvirtd.enable = lib.mkDefault false;
}
