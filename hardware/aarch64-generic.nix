# Portable aarch64 overlay — import when building host-aarch64 / ARM boards.
{ lib, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  hardware.enableRedistributableFirmware = true;
  # KVM on ARM where available
  boot.kernelModules = [ "kvm" ];
}
