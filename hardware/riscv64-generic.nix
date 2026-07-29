# Portable riscv64 overlay — auto-imported for host-riscv64.
# Needs a board/SoC with Linux + working KVM (or microvm-capable QEMU).
{ lib, pkgs, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "riscv64-linux";
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "kvm" ];

  environment.systemPackages = lib.mkAfter [
    pkgs.qemu_kvm
  ];
}
