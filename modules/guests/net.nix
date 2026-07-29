# netVM — sole egress; Nym / i2p / Tor; DNS/NTP; SOCKS frontends per zone
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

  # LAN SOCKS frontends on 10.0.0.1:
  #   nym: port        → 127.0.0.1:1070
  #   i2p: port+1000   → 127.0.0.1:4447
  #   tor: port+2000   → 127.0.0.1:9050
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
          description = "${backend} SOCKS :${toString (port + offset)} zone ${zone}";
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
    torsocks
    i2pd
    nftables
    dig
    tcpdump
    curl
    socat
  ];

  services.tor = {
    enable = true;
    client.enable = true;
    settings.SocksPort = [ "127.0.0.1:9050" ];
  };

  services.i2pd = {
    enable = true;
    enableIPv6 = false;
    address = "127.0.0.1";
    proto.socksProxy.enable = true;
    proto.socksProxy.address = "127.0.0.1";
    proto.socksProxy.port = 4447;
    proto.socksProxy.outproxyEnable = true;
    proto.http.enable = true;
    proto.http.address = "127.0.0.1";
    proto.http.port = 7070;
  };

  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [
          "10.0.0.1"
          "127.0.0.1"
        ];
        access-control = [
          "10.0.0.0/24 allow"
          "127.0.0.0/8 allow"
        ];
        do-not-query-localhost = "yes";
      };
      forward-zone = [
        {
          name = ".";
          forward-addr = [
            "1.1.1.1"
            "9.9.9.9"
          ];
        }
      ];
    };
  };

  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.0.1";
      prefixLength = 24;
    }
  ];
  networking.interfaces.eth1.useDHCP = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall.allowedTCPPorts = [
    53
    9050
    4447
  ]
  ++ lib.attrValues zoneSocks
  ++ map (p: p + 1000) (lib.attrValues zoneSocks)
  ++ map (p: p + 2000) (lib.attrValues zoneSocks);
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.extraCommands = ''
    iptables -t nat -A POSTROUTING -s 10.0.0.0/24 ! -d 10.0.0.0/24 -o eth1 -j MASQUERADE || true
  '';

  users.users.nym = {
    isSystemUser = true;
    group = "nym";
    home = "/var/lib/nym";
    createHome = true;
  };
  users.groups.nym = { };

  systemd.services = {
    nym-client = {
      description = "Single Nym client (ONE mixnet identity — Nym limitation)";
      after = [
        "network-online.target"
        "sys-subsystem-net-devices-eth0.device"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "nym";
        Group = "nym";
        StateDirectory = "nym/bunker";
        WorkingDirectory = "/var/lib/nym/bunker";
        ExecStartPre = pkgs.writeShellScript "nym-init-bunker" ''
          set -euo pipefail
          export HOME=/var/lib/nym
          mkdir -p /var/lib/nym/bunker
          cd /var/lib/nym/bunker
          if [ ! -f config.toml ] && [ ! -f config.yaml ] && [ ! -d config ] && [ ! -d .nym ]; then
            ${nymBin} init --id bunker || ${nymBin} init --id bunker --output /var/lib/nym/bunker || {
              echo "init failed — see docs/egress.md" >&2
              exit 1
            }
          fi
        '';
        ExecStart = pkgs.writeShellScript "nym-run-bunker" ''
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
    [
      "# 10.0.0.1 SOCKS — set zones.json internet=nym|i2p|tor|none"
      "# nym = ONE shared identity; i2p = i2pd outproxy alternative; tor = tor socks"
    ]
    ++ lib.mapAttrsToList (
      zone: port:
      "${zone} nym=${toString port} i2p=${toString (port + 1000)} tor=${toString (port + 2000)}"
    ) zoneSocks
  );

  environment.variables.BUNKER_ZONE = "net";
  services.timesyncd.enable = true;
}
