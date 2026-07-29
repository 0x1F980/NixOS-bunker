# usbVM — USB broker (1 → many zones), like netVM for network.
# Physical devices attach HERE via host QMP; app zones pull via usbip from 10.0.0.2.
{ pkgs, lib, ... }:

let
  usbip = pkgs.linuxPackages.usbip;
  broker = pkgs.writeShellScriptBin "bunker-usb-broker" ''
    set -euo pipefail
    USBIP="${usbip}/bin/usbip"
    CMD="''${1:-}"
    DEVID="''${2:-}"

    find_busid() {
      local want="$1"
      local v="''${want%:*}" p="''${want#*:}"
      v=$(echo "$v" | tr 'A-F' 'a-f')
      p=$(echo "$p" | tr 'A-F' 'a-f')
      for d in /sys/bus/usb/devices/*; do
        [ -f "$d/idVendor" ] && [ -f "$d/idProduct" ] || continue
        vv=$(cat "$d/idVendor")
        pp=$(cat "$d/idProduct")
        if [ "$vv" = "$v" ] && [ "$pp" = "$p" ]; then
          # usbip wants busid like 1-1.2
          basename "$d"
          return 0
        fi
      done
      return 1
    }

    case "$CMD" in
      busid)
        find_busid "$DEVID"
        ;;
      bind)
        BUS=$(find_busid "$DEVID") || {
          echo "ERROR: $DEVID not present on usbVM (QMP attach first)" >&2
          exit 1
        }
        # Idempotent: already exported is OK
        if ! $USBIP list -l 2>/dev/null | grep -qE "busid $BUS "; then
          $USBIP bind -b "$BUS"
        fi
        echo "$BUS"
        ;;
      unbind)
        BUS=$(find_busid "$DEVID" 2>/dev/null || true)
        if [ -n "''${BUS:-}" ]; then
          $USBIP unbind -b "$BUS" || true
        fi
        ;;
      list)
        echo "== lsusb =="; lsusb || true
        echo "== usbip list -l =="; $USBIP list -l || true
        echo "== usbip list -r localhost =="; $USBIP list -r 127.0.0.1 || true
        ;;
      *)
        echo "usage: bunker-usb-broker busid|bind|unbind|list <vid:pid>" >&2
        exit 1
        ;;
    esac
  '';
in
{
  microvm.mem = 512;
  microvm.vcpu = 1;

  boot.kernelModules = [
    "usbip_core"
    "usbip_host"
  ];

  environment.systemPackages = with pkgs; [
    usbutils
    pciutils
    usbip
    broker
  ];

  services.openssh.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    22
    3240
  ];
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

  security.sudo.extraRules = [
    {
      users = [ "zone" ];
      commands = [
        {
          command = "${usbip}/bin/usbip";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${broker}/bin/bunker-usb-broker";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.usbutils}/bin/lsusb";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  systemd.services.usbipd = {
    description = "USB/IP daemon — export devices to app zones";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "forking";
      ExecStart = "${usbip}/bin/usbipd -D";
      Restart = "on-failure";
    };
  };

  environment.variables.BUNKER_ZONE = "usb";

  environment.etc."bunker/usb-policy".text = ''
    usbVM (10.0.0.2) = USB broker (1 → many), same idea as netVM for network.
    Host QMP attaches physical USB ONLY to usbVM.
    App zones import with usbip: bunker-usb-attach <zone> <vid:pid>
  '';
}
