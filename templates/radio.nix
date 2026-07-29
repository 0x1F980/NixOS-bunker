# Template: radio — SDR / RF tools (attach dongles via bunker-usb-attach)
{ pkgs, lib, ... }:

let
  # Soft-deps: skip attrs missing on this arch/nixpkgs instead of failing eval
  maybe =
    name:
    if pkgs ? ${name} then [ pkgs.${name} ] else [ ];
in
{
  imports = [ ./desktop.nix ];

  environment.systemPackages =
    with pkgs;
    [
      wireshark
      gqrx
      rtl-sdr
      hackrf
      rtl_433
    ]
    ++ maybe "urh"
    ++ maybe "sdrpp"
    ++ maybe "sigdigger"
    ++ maybe "meshtastic";

  hardware.enableAllFirmware = lib.mkDefault false;
  hardware.enableRedistributableFirmware = true;
}
