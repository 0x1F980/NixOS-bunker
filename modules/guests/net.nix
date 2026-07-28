# netVM — sole egress; Nym/Tor/i2pd; DNS/NTP authority; SOCKS per app-zone
{ pkgs, lib, config, ... }:

{
  microvm.mem = 1024;
  microvm.vcpu = 2;
  microvm.interfaces = [
    {
      type = "tap";
      id = "vm-net";
      mac = "02:b0:00:00:00:01";
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
  ];

  # Tor daemon (optional alongside Nym)
  services.tor = {
    enable = true;
    client.enable = true;
    settings = {
      SocksPort = [
        # reserved / fallback — primary zone SOCKS are Nym below
        "9050"
      ];
    };
  };

  services.i2pd = {
    enable = true;
    enableIPv6 = false;
  };

  # DNS for guests
  services.unbound = {
    enable = true;
    settings.server = {
      interface = [ "10.0.0.1" ];
      access-control = [ "10.0.0.0/24 allow" ];
      # Forward only through Tor/Nym-aware paths in production — start conservative
      do-not-query-localhost = true;
    };
  };

  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.0.1";
      prefixLength = 24;
    }
  ];

  networking.firewall.allowedTCPPorts = [
    53
    1081 # personal Nym SOCKS
    1082 # work
    1083 # browse
    1084 # sdr
    9050 # tor fallback
  ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  # Nym SOCKS listeners — one identity/path per zone (configure credentials under /var/lib/nym)
  # Placeholders: operator runs nym-client per zone; systemd templates below.
  systemd.services."nym-socks@" = {
    description = "Nym SOCKS client for zone %i";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      User = "nym";
      StateDirectory = "nym/%i";
      ExecStart = "${pkgs.nym}/bin/nym-client run --id %i";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  users.users.nym = {
    isSystemUser = true;
    group = "nym";
    home = "/var/lib/nym";
    createHome = true;
  };
  users.groups.nym = { };

  # Enable zone SOCKS units (operator must init nym-client ids first)
  # systemd.targets.nym-zones.wants = [ "nym-socks@personal.service" ... ];

  environment.etc."bunker/nym-ports".text = ''
    personal 1081
    work     1082
    browse   1083
    sdr      1084
  '';

  environment.variables.BUNKER_ZONE = "net";

  # NTP only here — guests disable timesyncd
  services.timesyncd.enable = true;
}
