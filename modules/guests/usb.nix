# usbVM — USB device broker; attach one device to one app-VM at a time (host scripts)
{ pkgs, lib, ... }:

{
  microvm.mem = 512;
  microvm.vcpu = 1;

  environment.systemPackages = with pkgs; [
    usbutils
    pciutils
  ];

  # Minimal — no app template
  services.openssh.enable = true;
  networking.firewall.enable = true;
  networking.useDHCP = false;
  microvm.interfaces = [
    {
      type = "bridge";
      id = "vm-usb";
      mac = "02:b0:00:00:00:02";
      bridge = "br-bunker";
    }
  ];
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.0.2";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = {
    address = "10.0.0.1";
    interface = "eth0";
  };

  environment.variables.BUNKER_ZONE = "usb";

  environment.etc."bunker/usb-policy".text = ''
    # One physical USB device -> one target VM at a time.
    # Use on host: bunker-usb-attach <vm> <vendorId:productId>
    # Use on host: bunker-usb-detach <vm> <vendorId:productId>
  '';
}
