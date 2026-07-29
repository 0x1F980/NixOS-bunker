# Build one app-zone NixOS module from a zones.nix entry.
# Usage (from flake): import ./modules/guests/mk-app-zone.nix { inherit name zone; }
{
  name,
  zone,
}:
{
  pkgs,
  lib,
  config,
  ...
}:

let
  templatePath = ../../templates/${zone.template}.nix;
  socks = zone.socks or null;
  disposable = zone.disposable or false;
  mem = zone.mem or 1536;
  vcpu = zone.vcpu or 2;
  ip = zone.ip;
  mac = zone.mac;
in
{
  imports = [ templatePath ];

  microvm.mem = mem;
  microvm.vcpu = vcpu;
  microvm.interfaces = [
    {
      type = "bridge";
      id = "vm-${name}";
      inherit mac;
      bridge = "br-bunker";
    }
  ];

  networking.useDHCP = false;
  networking.nameservers = [ "10.0.0.1" ];
  networking.defaultGateway = {
    address = "10.0.0.1";
    interface = "eth0";
  };
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = ip;
      prefixLength = 24;
    }
  ];

  environment.variables = {
    BUNKER_ZONE = name;
  }
  // lib.optionalAttrs (socks != null) {
    ALL_PROXY = "socks5h://10.0.0.1:${toString socks}";
    HTTPS_PROXY = "socks5h://10.0.0.1:${toString socks}";
    HTTP_PROXY = "socks5h://10.0.0.1:${toString socks}";
  }
  // lib.optionalAttrs disposable {
    BUNKER_DISPOSABLE = "1";
  };

  environment.etc."bunker/zone.json".text = builtins.toJSON {
    inherit name ip mac socks disposable mem vcpu;
    template = zone.template;
  };

  # Disposable: prefer no long-lived secrets; wipe via bunker-wipe <zone>
  services.openssh.enable = true;
}
