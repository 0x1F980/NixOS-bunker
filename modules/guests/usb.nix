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
  services.openssh.enable = false;
  networking.firewall.enable = true;

  environment.variables.BUNKER_ZONE = "usb";

  # Guests receive USB via host qemu device_add / microvm hotplug driven by scripts/usb-attach.sh
  environment.etc."bunker/usb-policy".text = ''
    # One physical USB device -> one target VM at a time.
    # Use on host: bunker-usb-attach <vm> <busid>
    # Use on host: bunker-usb-detach <vm> <busid>
  '';
}
