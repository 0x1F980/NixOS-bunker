# Shared microVM guest base — every AppVM / Disposable / Service guest.
# No SPICE clipboard; QMP socket for host-mediated USB to usbVM only.
{
  config,
  lib,
  pkgs,
  bunkerZone ? "guest",
  ...
}:

{
  # microVM defaults
  microvm = {
    hypervisor = "qemu";
    # On-demand RAM; adjust per zone overlays
    mem = lib.mkDefault 1024;
    vcpu = lib.mkDefault 2;
    # QMP: usbVM uses this for physical usb-host; app zones mostly usbip
    socket = lib.mkDefault "/run/microvm/${config.networking.hostName}.sock";
    qemu.extraArgs = [
      "-device"
      "virtio-rng-pci"
      "-device"
      "qemu-xhci,id=xhci"
    ];
    # Do NOT share PipeWire / Wayland sockets by default
    # Do NOT enable guest→host clipboard channels
  };

  boot.isContainer = false;
  services.getty.autologinUser = lib.mkDefault "zone";

  users.users.zone = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "audio"
    ];
    initialPassword = "zone";
  };

  # Unique machine-id placeholder — regenerated per instance via activation
  environment.etc."machine-id-template" = {
    text = "";
    mode = "0444";
  };

  system.activationScripts.uniqueMachineId = ''
    if [ ! -s /etc/machine-id ]; then
      ${pkgs.coreutils}/bin/od -An -N16 -tx1 /dev/urandom | tr -d ' \n' > /etc/machine-id
    fi
  '';

  # microvm optimization enables networkd — set gateways with interface=eth0 in zone modules

  # Portable guest hardening subset
  networking.firewall.enable = true;
  networking.firewall.allowPing = false;
  # SSH only for host→guest clipboard / admin from bunker LAN
  services.openssh = {
    enable = lib.mkDefault true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };
  networking.firewall.extraCommands = lib.mkAfter ''
    iptables -C INPUT -p tcp -s 10.0.0.0/24 --dport 22 -j ACCEPT 2>/dev/null || \
      iptables -I INPUT -p tcp -s 10.0.0.0/24 --dport 22 -j ACCEPT
  '';
  services.avahi.enable = false;
  services.printing.enable = false;
  hardware.bluetooth.enable = false;
  systemd.coredump.enable = false;

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
  };

  # usbip client so app zones can pull devices from usbVM (10.0.0.2)
  boot.kernelModules = lib.mkAfter [
    "vhci_hcd"
    "usbip_core"
  ];
  environment.systemPackages = lib.mkAfter [ pkgs.linuxPackages.usbip ];
  security.sudo.extraRules = lib.mkAfter [
    {
      users = [ "zone" ];
      commands = [
        {
          command = "${pkgs.linuxPackages.usbip}/bin/usbip";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "obsidian" ];

  environment.variables.BUNKER_ZONE = bunkerZone;

  system.stateVersion = "26.05";
}
