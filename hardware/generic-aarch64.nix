# Portable aarch64 overlay — KVM where available (not Xen, not vendor-locked).
{ lib, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "kvm" ];
  # Many boards need device-tree / vendor firmware from nixos-generate-config.
  virtualisation.libvirtd.enable = lib.mkDefault false;
}
