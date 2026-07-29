# Fallback hardware overlay for any Linux ISA without a dedicated file.
# Sets platform + best-effort KVM; board firmware still comes from hardware-configuration.nix.
{ lib, pkgs, ... }:

{
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = lib.mkDefault [ "kvm" ];
  environment.systemPackages = lib.mkAfter [ pkgs.qemu_kvm ];
}
