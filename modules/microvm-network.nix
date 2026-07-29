# Host-side microVM network: bridge br-bunker (10.0.0.254/24).
# Guests use type=bridge → br-bunker (microvm.nix attaches taps).
# netVM is 10.0.0.1 (gateway + SOCKS for app VMs). Host is .254 for management.
{
  config,
  lib,
  pkgs,
  bunkerAppZones ? import ../config/zones.nix,
  ...
}:

let
  appTapNames = lib.mapAttrsToList (name: _: "vm-${name}") bunkerAppZones;
  tapNames = [
    "vm-net"
    "vm-usb"
    "vm-voice"
  ]
  ++ appTapNames;
in
{
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.bridges.br-bunker.interfaces = [ ];

  networking.interfaces.br-bunker.ipv4.addresses = [
    {
      address = "10.0.0.254";
      prefixLength = 24;
    }
  ];

  networking.networkmanager.unmanaged = [
    "interface-name:br-bunker"
    "interface-name:vm-*"
  ];

  systemd.services.bunker-bridge-up = {
    description = "Bring up br-bunker for microVM LAN";
    after = [ "network-pre.target" ];
    before = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "bunker-bridge-up" ''
        set -euo pipefail
        ${pkgs.iproute2}/bin/ip link add name br-bunker type bridge 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set br-bunker up
        ${pkgs.iproute2}/bin/ip addr replace 10.0.0.254/24 dev br-bunker
      '';
    };
  };

  systemd.services.bunker-bridge-attach = {
    description = "Attach bunker microVM taps to br-bunker";
    after = [
      "bunker-bridge-up.service"
      "network-online.target"
    ];
    wants = [
      "bunker-bridge-up.service"
      "network-online.target"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "bunker-bridge-attach" ''
        set -euo pipefail
        ${pkgs.iproute2}/bin/ip link set br-bunker up || true
        for tap in ${lib.concatStringsSep " " tapNames}; do
          if ${pkgs.iproute2}/bin/ip link show "$tap" >/dev/null 2>&1; then
            ${pkgs.iproute2}/bin/ip link set "$tap" master br-bunker
            ${pkgs.iproute2}/bin/ip link set "$tap" up
          fi
        done
      '';
    };
  };

  environment.etc."bunker/network".text = ''
    Bridge: br-bunker 10.0.0.254/24
    netVM:  10.0.0.1   (gateway + Nym/DNS; WAN via user-net)
    App zones: see /etc/bunker/zones.tsv (from config/zones.nix)
    vault: no NIC
    usb:   10.0.0.2

    App VMs must NOT NAT to clearnet on the host. Use bunker-killswitch enable.
    Only vm-net may forward to WAN.
  '';

  networking.firewall.extraCommands = lib.mkAfter ''
    iptables -C FORWARD -i br-bunker -o br-bunker -j ACCEPT 2>/dev/null || \
      iptables -A FORWARD -i br-bunker -o br-bunker -j ACCEPT
  '';
}
