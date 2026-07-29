# Template: radio — SDR / RF tools (attach dongles via bunker-usb-attach)
{ pkgs, lib, ... }:

{
  imports = [ ./desktop.nix ];

  environment.systemPackages = with pkgs; [
    wireshark
    gqrx
    rtl-sdr
    hackrf
    urh
    rtl_433
    sdrpp
    sigdigger
    meshtastic
  ];

  hardware.enableAllFirmware = lib.mkDefault false;
  hardware.enableRedistributableFirmware = true;
}
