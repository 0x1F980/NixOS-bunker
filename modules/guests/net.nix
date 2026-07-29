# netVM — sole egress; Nym/Tor/i2pd; DNS/NTP; SOCKS per app-zone from config/zones.nix
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
in
{
  microvm.mem = 1024;
  microvm.vcpu = 2;

  microvm.volumes = [
    {
      image = "nym-state.img";
      mountPoint = "/var/lib/nym";
      size = 512;
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
  ]
  ++ lib.attrValues zoneSocks;
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

  # Nym allows only ONE mixnet identity/client at a time.
  # All zone SOCKS ports (1081…) are local frontends → that single client.
  # Contaminations note: app zones share the same Nym identity on the wire.
  systemd.services.nym-client = {
    description = "Single Nym client (shared by all zone SOCKS ports)";
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
            echo "init failed — see docs/nym-bootstrap.md" >&2
            exit 1
          }
        fi
      '';
      ExecStart = pkgs.writeShellScript "nym-run-bunker" ''
        set -euo pipefail
        export HOME=/var/lib/nym
        # Internal SOCKS for socat frontends
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

  systemd.services =
    (lib.mapAttrs' (
      zone: port:
      lib.nameValuePair "nym-socks-${zone}" {
        description = "SOCKS frontend :${toString port} → single Nym client (zone ${zone})";
        after = [ "nym-client.service" ];
        requires = [ "nym-client.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString port},bind=10.0.0.1,fork,reuseaddr TCP:127.0.0.1:1070";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      }
    ) zoneSocks)
    // {
      bunker-tor-socks-fallback = {
        description = "Optional Tor SOCKS fallback for all zone SOCKS ports";
        after = [ "tor.service" ];
        wantedBy = [ ];
        serviceConfig = {
          Type = "simple";
          ExecStart = pkgs.writeShellScript "tor-socks-fallback" ''
            set -euo pipefail
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                _: port:
                "${pkgs.socat}/bin/socat TCP-LISTEN:${toString port},bind=10.0.0.1,fork,reuseaddr TCP:127.0.0.1:9050 &"
              ) zoneSocks
            )}
            wait
          '';
          Restart = "on-failure";
        };
      };
    };

  environment.etc."bunker/nym-ports".text = lib.concatStringsSep "\n" (
    [
      "# ONE nym-client identity (bunker); zone ports are frontends only"
      "nym-client 127.0.0.1:1070"
    ]
    ++ lib.mapAttrsToList (zone: port: "${zone} ${toString port} -> nym-client") zoneSocks
    ++ [ "tor-fallback 9050" ]
  );

  environment.variables.BUNKER_ZONE = "net";
  services.timesyncd.enable = true;
}
