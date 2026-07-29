# Portable x86_64 overlay — auto-imported for host / host builds on x86_64.
{ lib, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  # Load whichever matches the CPU; the other is a no-op.
  boot.kernelModules = [
    "kvm-intel"
    "kvm-amd"
  ];
  virtualisation.libvirtd.enable = lib.mkDefault false;
}
