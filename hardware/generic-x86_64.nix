# Portable x86_64 overlay — import from hosts/bunker/configuration.nix when needed.
{ lib, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "kvm-intel" ];
}
