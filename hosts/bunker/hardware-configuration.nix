# STUB — replace on the target machine:
#   sudo nixos-generate-config --show-hardware-config > hosts/bunker/hardware-configuration.nix
#
# Platform-agnostic stub — evaluate on x86_64 / aarch64 / riscv64.
# Flake: .#host-<system> + hardware/default.nix picks KVM overlay.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "virtio_pci"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = [ ];
  # KVM module names come from hardware/generic-{x86_64,aarch64,riscv64}.nix
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Placeholder root — MUST be replaced with real LUKS/filesystems from nixos-generate-config.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
}
