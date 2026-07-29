# sdr zone — radio / recon stack
{ pkgs, lib, ... }:

{
  imports = [ ./template.nix ];

  microvm.mem = 1920;
  microvm.interfaces = [
    {
      type = "bridge";
      id = "vm-sdr";
      mac = "02:b0:00:00:00:14";
      bridge = "br-bunker";
    }
  ];

  networking.useDHCP = false;
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

  # USB radio dongles attached via host usb-attach → this VM only
  hardware.enableAllFirmware = lib.mkDefault false;
  hardware.enableRedistributableFirmware = true;

  environment.variables = {
    BUNKER_ZONE = "sdr";
    ALL_PROXY = "socks5h://10.0.0.1:1084";
    HTTPS_PROXY = "socks5h://10.0.0.1:1084";
    HTTP_PROXY = "socks5h://10.0.0.1:1084";
  };

  networking.defaultGateway = lib.mkDefault {
    address = "10.0.0.1";
    interface = "eth0";
  };
  networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [
    {
      address = "10.0.0.14";
      prefixLength = 24;
    }
  ];
}
