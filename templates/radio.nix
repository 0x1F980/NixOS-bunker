# Radio / SDR — attach dongle via bunker-usb-attach.
{ pkgs, ... }:

{
  imports = [ ./desktop.nix ];
  environment.systemPackages = with pkgs; [
    gqrx
    rtl-sdr
    rtl_433
  ];
  hardware.enableRedistributableFirmware = true;
}
