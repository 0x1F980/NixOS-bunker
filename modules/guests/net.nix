# netVM — sole egress; Nym/Tor/i2pd; DNS/NTP; SOCKS per app-zone
{ pkgs, lib, config, ... }:

let
  zoneSocks = {
    personal = 1081;
    work = 1082;
    browse = 1083;
    sdr = 1084;
  };
  nymBin = "${pkgs.nym}/bin/nym-client";
in
{
  microvm.mem = 1024;
  microvm.vcpu = 2;

  # Persistent Nym state across reboots
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
    # SLIRP/user-net: mixnet + DNS upstream without host NAT gymnastics
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
  # eth1 = user-net (DHCP from SLIRP) for WAN
  networking.interfaces.eth1.useDHCP = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall.allowedTCPPorts = [
    53
    1081
    1082
    1083
    1084
    9050
  ];
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

  systemd.services =
    (lib.mapAttrs' (
      zone: port:
      lib.nameValuePair "nym-socks-${zone}" {
        description = "Nym SOCKS for bunker zone ${zone} on :${toString port}";
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
          StateDirectory = "nym/${zone}";
          WorkingDirectory = "/var/lib/nym/${zone}";
          # Init once; fail the start (not silently) if binary missing
          ExecStartPre = pkgs.writeShellScript "nym-init-${zone}" ''
            set -euo pipefail
            export HOME=/var/lib/nym
            mkdir -p /var/lib/nym/${zone}
            cd /var/lib/nym/${zone}
            if [ ! -f config.toml ] && [ ! -f config.yaml ] && [ ! -d config ] && [ ! -d .nym ]; then
              echo "nym-client not initialized for ${zone}; run docs/nym-bootstrap.md"
              ${nymBin} init --id ${zone} || ${nymBin} init --id ${zone} --output /var/lib/nym/${zone} || {
                echo "init failed — see docs/nym-bootstrap.md" >&2
                exit 1
              }
            fi
          '';
          ExecStart = pkgs.writeShellScript "nym-run-${zone}" ''
            set -euo pipefail
            export HOME=/var/lib/nym
            # Prefer explicit SOCKS bind; fall back to plain run (bootstrap may still need help)
            if ${nymBin} run --help 2>&1 | grep -qiE 'socks5|socks-bind|socks5-bind'; then
              exec ${nymBin} run --id ${zone} --socks5-bind 0.0.0.0:${toString port}
            else
              echo "WARN: nym-client has no socks bind flag; starting without LAN SOCKS" >&2
              exec ${nymBin} run --id ${zone}
            fi
          '';
          Restart = "on-failure";
          RestartSec = "15s";
        };
      }
    ) zoneSocks)
    // {
      bunker-tor-socks-fallback = {
        description = "Optional Tor SOCKS fallback on 1081-1084 when nym down";
        after = [ "tor.service" ];
        wantedBy = [ ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.socat}/bin/socat TCP-LISTEN:1081,bind=10.0.0.1,fork,reuseaddr TCP:127.0.0.1:9050 & ${pkgs.socat}/bin/socat TCP-LISTEN:1082,bind=10.0.0.1,fork,reuseaddr TCP:127.0.0.1:9050 & ${pkgs.socat}/bin/socat TCP-LISTEN:1083,bind=10.0.0.1,fork,reuseaddr TCP:127.0.0.1:9050 & ${pkgs.socat}/bin/socat TCP-LISTEN:1084,bind=10.0.0.1,fork,reuseaddr TCP:127.0.0.1:9050 & wait'";
          Restart = "on-failure";
        };
      };
    };

  environment.etc."bunker/nym-ports".text = ''
    personal 1081
    work     1082
    browse   1083
    sdr      1084
    tor-fallback 9050
  '';

  environment.variables.BUNKER_ZONE = "net";
  services.timesyncd.enable = true;
}
