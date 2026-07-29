# Optional MacBookAir5,2 overlay — board-specific; NOT imported by default.
# Portable-first defaults: hardware/generic-linux.nix + hosts/bunker/hardware-configuration.nix.
{
  lib,
  pkgs,
  ...
}:

{
  boot.kernelModules = [
    "kvm-intel"
    "applesmc"
  ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Broadcom Wi-Fi common on MBA52 — enable only if you need it
  # hardware.enableAllFirmware = true;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # Intel HD 4000
  services.xserver.videoDrivers = lib.mkDefault [ "modesetting" ];
  environment.systemPackages = [ pkgs.mesa-demos ];
}
