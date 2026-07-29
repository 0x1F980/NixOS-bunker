# personal zone — template + private profile
{ lib, ... }:

{
  imports = [ ./template.nix ];

  microvm.mem = 1536;
  microvm.interfaces = [
    {
      type = "bridge";
      id = "vm-personal";
      mac = "02:b0:00:00:00:11";
      bridge = "br-bunker";
    }
  ];

  networking.useDHCP = false;
  # Egress only via netVM Nym SOCKS for personal (port convention)
  environment.variables = {
    BUNKER_ZONE = "personal";
    ALL_PROXY = "socks5h://10.0.0.1:1081";
    HTTPS_PROXY = "socks5h://10.0.0.1:1081";
    HTTP_PROXY = "socks5h://10.0.0.1:1081";
  };

  networking.defaultGateway = lib.mkDefault {
    address = "10.0.0.1";
    interface = "eth0";
  };
  networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [
    {
      address = "10.0.0.11";
      prefixLength = 24;
    }
  ];
}
