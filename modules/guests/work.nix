# work zone — template + development / AI
{ pkgs, lib, ... }:

{
  imports = [ ./template.nix ];

  microvm.mem = 2048;
  microvm.vcpu = 2;
  microvm.interfaces = [
    {
      type = "tap";
      id = "vm-work";
      mac = "02:b0:00:00:00:12";
    }
  ];

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

  networking.defaultGateway = lib.mkDefault "10.0.0.1";
  networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [
    {
      address = "10.0.0.12";
      prefixLength = 24;
    }
  ];
}
