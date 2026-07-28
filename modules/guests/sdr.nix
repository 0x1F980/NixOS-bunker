# sdr zone — radio / recon stack
{ pkgs, lib, ... }:

{
  imports = [ ./template.nix ];

  microvm.mem = 2048;
  microvm.interfaces = [
    {
      type = "tap";
      id = "vm-sdr";
      mac = "02:b0:00:00:00:14";
    }
  ];

  environment.systemPackages = with pkgs; [
    wireshark
    # sigdigger / sdrpp may vary by nixpkgs channel — include when available
    gqrx
    rtl-sdr
    hackrf
    urh
    rtl_433
    # meshtastic — python package often as meshtastic CLI
  ]
  ++ lib.optional (pkgs ? sdrpp) pkgs.sdrpp
  ++ lib.optional (pkgs ? sigdigger) pkgs.sigdigger
  ++ lib.optional (pkgs ? meshtastic) pkgs.meshtastic;

  # USB radio dongles attached via host usb-attach → this VM only
  hardware.enableAllFirmware = lib.mkDefault false;
  hardware.enableRedistributableFirmware = true;

  environment.variables = {
    BUNKER_ZONE = "sdr";
    ALL_PROXY = "socks5h://10.0.0.1:1084";
    HTTPS_PROXY = "socks5h://10.0.0.1:1084";
    HTTP_PROXY = "socks5h://10.0.0.1:1084";
  };

  networking.defaultGateway = lib.mkDefault "10.0.0.1";
  networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [
    {
      address = "10.0.0.14";
      prefixLength = 24;
    }
  ];
}
