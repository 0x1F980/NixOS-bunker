# Portable aarch64 overlay — auto-imported for host-aarch64.
# Boards: Asahi/Apple Silicon (Linux), RPi4/5, Ampere, etc. — need working KVM.
{ lib, pkgs, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "kvm" ];

  # Prefer qemu-system-aarch64 + kvm when available
  environment.systemPackages = lib.mkAfter [
    pkgs.qemu_kvm
  ];
}
