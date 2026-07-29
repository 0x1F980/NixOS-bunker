# work zone — template + development / AI
{ pkgs, lib, ... }:

{
  imports = [ ./template.nix ];

  microvm.mem = 1920;
  microvm.vcpu = 2;
  microvm.interfaces = [
    {
      type = "bridge";
      id = "vm-work";
      mac = "02:b0:00:00:00:12";
      bridge = "br-bunker";
    }
  ];

  networking.useDHCP = false;
  environment.systemPackages = with pkgs; [
    vscodium
    ollama
    git
    gcc
    clang
    kdenlive
    libsodium
  ];

  environment.variables = {
    BUNKER_ZONE = "work";
    ALL_PROXY = "socks5h://10.0.0.1:1082";
    HTTPS_PROXY = "socks5h://10.0.0.1:1082";
    HTTP_PROXY = "socks5h://10.0.0.1:1082";
  };

  networking.defaultGateway = lib.mkDefault {
    address = "10.0.0.1";
    interface = "eth0";
  };
  networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [
    {
      address = "10.0.0.12";
      prefixLength = 24;
    }
  ];
}
