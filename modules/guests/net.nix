# netVM — egress: Nym / i2p / Tor SOCKS frontends per zone + 2-hop cascades + DNS.
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

  mkTorCascade =
    {
      name,
      socksPort,
      upstream,
      after,
    }:
    {
      description = "Tor client cascaded over ${upstream}";
      after = [ "network-online.target" ] ++ after;
      wants = [ "network-online.target" ] ++ after;
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "tor-cascade";
        Group = "tor-cascade";
        StateDirectory = "tor-cascade/${name}";
        ExecStart = "${pkgs.tor}/bin/tor -f ${pkgs.writeText "torrc-${name}" ''
          DataDirectory /var/lib/tor-cascade/${name}
          SocksPort 127.0.0.1:${toString socksPort}
          Socks5Proxy ${upstream}
          AutomapHostsOnResolve 1
          AvoidDiskWrites 1
        ''}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

  mkNymVia =
    {
      name,
      id,
      socksBind,
      proxyEnv,
      after,
    }:
    {
      description = "Nym client (${name}) via upstream SOCKS";
      after = [ "network-online.target" ] ++ after;
      wants = [ "network-online.target" ] ++ after;
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "nym";
        Group = "nym";
        StateDirectory = "nym/${id}";
        WorkingDirectory = "/var/lib/nym/${id}";
        Environment = [ "ALL_PROXY=${proxyEnv}" "HTTPS_PROXY=${proxyEnv}" "HTTP_PROXY=${proxyEnv}" ];
        ExecStartPre = pkgs.writeShellScript "nym-init-${id}" ''
          set -euo pipefail
          export HOME=/var/lib/nym
          mkdir -p /var/lib/nym/${id}
          cd /var/lib/nym/${id}
          if [ ! -f config.toml ] && [ ! -f config.yaml ] && [ ! -d config ] && [ ! -d .nym ]; then
            ${nymBin} init --id ${id} || ${nymBin} init --id ${id} --output /var/lib/nym/${id} || exit 1
          fi
        '';
        ExecStart = pkgs.writeShellScript "nym-run-${id}" ''
          set -euo pipefail
          export HOME=/var/lib/nym
          export ALL_PROXY='${proxyEnv}' HTTPS_PROXY='${proxyEnv}' HTTP_PROXY='${proxyEnv}'
          if ${nymBin} run --help 2>&1 | grep -qiE 'socks5|socks-bind|socks5-bind'; then
            exec ${nymBin} run --id ${id} --socks5-bind ${socksBind}
          else
            exec ${nymBin} run --id ${id}
          fi
        '';
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };

  # Naming: inner-outer = guest speaks to outer, outer tunnels via inner.
  # Ports: nym+0 · i2p+1000 · tor+2000 · nym-tor+3000 · i2p-tor+4000 · tor-nym+5000 · i2p-nym+6000
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
        "nym-tor" = {
          offset = 3000;
          target = "127.0.0.1:9150";
          after = [
            "tor-cascade-nym.service"
            "nym-client.service"
          ];
          requires = [ "tor-cascade-nym.service" ];
        };
        "i2p-tor" = {
          offset = 4000;
          target = "127.0.0.1:9250";
          after = [
            "tor-cascade-i2p.service"
            "i2pd.service"
          ];
          requires = [ "tor-cascade-i2p.service" ];
        };
        "tor-nym" = {
          offset = 5000;
          target = "127.0.0.1:1071";
          after = [
            "nym-via-tor.service"
            "tor.service"
          ];
          requires = [ "nym-via-tor.service" ];
        };
        "i2p-nym" = {
          offset = 6000;
          target = "127.0.0.1:1072";
          after = [
            "nym-via-i2p.service"
            "i2pd.service"
          ];
          requires = [ "nym-via-i2p.service" ];
        };
      };
in
{
  microvm.mem = 1536;
  microvm.vcpu = 2;

  microvm.volumes = [
    {
      image = "nym-state.img";
      mountPoint = "/var/lib/nym";
      size = 1024;
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

  services.unbound.enable = false;

  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.0.1";
      prefixLength = 24;
    }
  ];
  networking.interfaces.eth1.useDHCP = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = 0;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 0;

  networking.firewall = {
    enable = true;
    allowPing = false;
    allowedTCPPorts = [ 22 53 ]
      ++ lib.attrValues zoneSocks
      ++ map (p: p + 1000) (lib.attrValues zoneSocks)
      ++ map (p: p + 2000) (lib.attrValues zoneSocks)
      ++ map (p: p + 3000) (lib.attrValues zoneSocks)
      ++ map (p: p + 4000) (lib.attrValues zoneSocks)
      ++ map (p: p + 5000) (lib.attrValues zoneSocks)
      ++ map (p: p + 6000) (lib.attrValues zoneSocks);
    allowedUDPPorts = [ 53 ];
    extraCommands = ''
      iptables -P FORWARD DROP || true
      iptables -F FORWARD || true
      iptables -t nat -D POSTROUTING -s 10.0.0.0/24 ! -d 10.0.0.0/24 -o eth1 -j MASQUERADE 2>/dev/null || true
      while iptables -t nat -C POSTROUTING -s 10.0.0.0/24 ! -d 10.0.0.0/24 -o eth1 -j MASQUERADE 2>/dev/null; do
        iptables -t nat -D POSTROUTING -s 10.0.0.0/24 ! -d 10.0.0.0/24 -o eth1 -j MASQUERADE || break
      done
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
  users.users.tor-cascade = {
    isSystemUser = true;
    group = "tor-cascade";
    home = "/var/lib/tor-cascade";
    createHome = true;
  };
  users.groups.tor-cascade = { };

  systemd.services = {
    tor-cascade-nym = mkTorCascade {
      name = "nym";
      socksPort = 9150;
      upstream = "127.0.0.1:1070";
      after = [ "nym-client.service" ];
    };
    tor-cascade-i2p = mkTorCascade {
      name = "i2p";
      socksPort = 9250;
      upstream = "127.0.0.1:4447";
      after = [ "i2pd.service" ];
    };
    nym-via-tor = mkNymVia {
      name = "via-tor";
      id = "bunker-tor";
      socksBind = "127.0.0.1:1071";
      proxyEnv = "socks5h://127.0.0.1:9050";
      after = [ "tor.service" ];
    };
    nym-via-i2p = mkNymVia {
      name = "via-i2p";
      id = "bunker-i2p";
      socksBind = "127.0.0.1:1072";
      proxyEnv = "socks5h://127.0.0.1:4447";
      after = [ "i2pd.service" ];
    };

    nym-client = {
      description = "Nym client (direct mixnet identity)";
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
      zone: port:
      "${zone} nym=${toString port} i2p=${toString (port + 1000)} tor=${toString (port + 2000)} nym-tor=${toString (port + 3000)} i2p-tor=${toString (port + 4000)} tor-nym=${toString (port + 5000)} i2p-nym=${toString (port + 6000)}"
    ) zoneSocks
  );

  environment.variables.BUNKER_ZONE = "net";
  services.timesyncd.enable = true;
}
