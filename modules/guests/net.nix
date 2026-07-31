# netVM — egress: Nym / i2p / Tor SOCKS frontends per zone + DNS.
{
  pkgs,
  lib,
  bunkerAppZones ? import ../../config/zones.nix,
  ...
}:

let
  zoneSocks = lib.mapAttrs (_: z: z.socks) (
    lib.filterAttrs (_: z: z ? socks && z.socks != null) bunkerAppZones
  );
  nymBin = "${pkgs.nym}/bin/nym-client";
  # nym=port → :1070 · i2p=port+1000 → :4447 · tor=port+2000 → :9050
  frontendServices =
    lib.concatMapAttrs (
      backend:
      {
        offset,
        target,
        after ? [ ],
        requires ? [ ],
      }:
      lib.mapAttrs' (
        zone: port:
        lib.nameValuePair "${backend}-socks-${zone}" {
          description = "${backend} SOCKS :${toString (port + offset)} ${zone}";
          after = [ "network-online.target" ] ++ after;
          wants = [ "network-online.target" ];
          requires = requires;
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString (port + offset)},bind=10.0.0.1,fork,reuseaddr TCP:${target}";
            Restart = "on-failure";
            RestartSec = "5s";
          };
        }
      ) zoneSocks
    )
      {
        nym = {
          offset = 0;
          target = "127.0.0.1:1070";
          after = [ "nym-client.service" ];
          requires = [ "nym-client.service" ];
        };
        i2p = {
          offset = 1000;
          target = "127.0.0.1:4447";
          after = [ "i2pd.service" ];
        };
        tor = {
          offset = 2000;
          target = "127.0.0.1:9050";
          after = [ "tor.service" ];
        };
      };
in
{
  microvm.mem = 1280;
  microvm.vcpu = 2;

  microvm.volumes = [
    {
      image = "nym-state.img";
      mountPoint = "/var/lib/nym";
      size = 512;
    }
    {
      image = "i2pd-state.img";
      mountPoint = "/var/lib/i2pd";
      size = 1024;
    }
  ];

  microvm.interfaces = [
    {
      type = "bridge";
      id = "vm-net";
      mac = "02:b0:00:00:00:01";
      bridge = "br-bunker";
    }
    {
      type = "user";
      id = "wan";
      mac = "02:b0:00:00:00:fe";
    }
  ];

  environment.systemPackages = with pkgs; [
    nym
    tor
    i2pd
    nftables
    socat
  ];

  services.tor = {
    enable = true;
    client.enable = true;
    settings = {
      SocksPort = [ "127.0.0.1:9050" ];
      # Guest DNS only via Tor — never clearnet unbound
      DNSPort = [ "10.0.0.1:53" ];
      AutomapHostsOnResolve = true;
    };
  };

  services.i2pd = {
    enable = true;
    enableIPv6 = false;
    address = "127.0.0.1";
    proto.socksProxy.enable = true;
    proto.socksProxy.address = "127.0.0.1";
    proto.socksProxy.port = 4447;
    proto.socksProxy.outproxyEnable = true;
  };

  # No guest clearnet DNS resolver. Guests use Tor DNSPort :53 or socks5h.
  services.unbound.enable = false;

  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.0.1";
      prefixLength = 24;
    }
  ];
  networking.interfaces.eth1.useDHCP = true;

  # HARD: guests must NOT be NATed to WAN. Only local SOCKS daemons egress.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 0;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 0;

  networking.firewall = {
    enable = true;
    allowPing = false;
    # LAN-facing services only (declared for NixOS firewall helpers)
    allowedTCPPorts = [ 22 53 ]
      ++ lib.attrValues zoneSocks
      ++ map (p: p + 1000) (lib.attrValues zoneSocks)
      ++ map (p: p + 2000) (lib.attrValues zoneSocks);
    allowedUDPPorts = [ 53 ];
    extraCommands = ''
      # Drop ALL forwarding (no guest→WAN via netVM)
      iptables -P FORWARD DROP || true
      iptables -F FORWARD || true
      # Strip any legacy guest MASQUERADE
      iptables -t nat -D POSTROUTING -s 10.0.0.0/24 ! -d 10.0.0.0/24 -o eth1 -j MASQUERADE 2>/dev/null || true
      while iptables -t nat -C POSTROUTING -s 10.0.0.0/24 ! -d 10.0.0.0/24 -o eth1 -j MASQUERADE 2>/dev/null; do
        iptables -t nat -D POSTROUTING -s 10.0.0.0/24 ! -d 10.0.0.0/24 -o eth1 -j MASQUERADE || break
      done
      # INPUT from bunker LAN: only SSH + DNS + SOCKS (already opened via allowed*Ports).
      # Reject anything else from LAN that is not established.
      iptables -C INPUT -i eth0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 1 -i eth0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    '';
  };

  users.users.nym = {
    isSystemUser = true;
    group = "nym";
    home = "/var/lib/nym";
    createHome = true;
  };
  users.groups.nym = { };

  systemd.services = {
    nym-client = {
      description = "Nym client (one shared mixnet identity)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "nym";
        Group = "nym";
        StateDirectory = "nym/bunker";
        WorkingDirectory = "/var/lib/nym/bunker";
        ExecStartPre = pkgs.writeShellScript "nym-init" ''
          set -euo pipefail
          export HOME=/var/lib/nym
          mkdir -p /var/lib/nym/bunker
          cd /var/lib/nym/bunker
          if [ ! -f config.toml ] && [ ! -f config.yaml ] && [ ! -d config ] && [ ! -d .nym ]; then
            ${nymBin} init --id bunker || ${nymBin} init --id bunker --output /var/lib/nym/bunker || exit 1
          fi
        '';
        ExecStart = pkgs.writeShellScript "nym-run" ''
          set -euo pipefail
          export HOME=/var/lib/nym
          if ${nymBin} run --help 2>&1 | grep -qiE 'socks5|socks-bind|socks5-bind'; then
            exec ${nymBin} run --id bunker --socks5-bind 127.0.0.1:1070
          else
            exec ${nymBin} run --id bunker
          fi
        '';
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };
  }
  // frontendServices;

  environment.etc."bunker/egress-ports".text = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      zone: port: "${zone} nym=${toString port} i2p=${toString (port + 1000)} tor=${toString (port + 2000)}"
    ) zoneSocks
  );

  environment.variables.BUNKER_ZONE = "net";
  services.timesyncd.enable = true;
}
