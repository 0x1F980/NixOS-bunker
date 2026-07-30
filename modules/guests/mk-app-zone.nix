# App-zone from zones.json (NixOS microVM — not ISO).
{
  name,
  zone,
}:
{
  pkgs,
  lib,
  ...
}:

let
  colors = import ../../config/colors.nix;
  disposable = zone.disposable or false;
  mem = zone.mem or 1536;
  vcpu = zone.vcpu or 2;
  ip = zone.ip;
  mac = zone.mac;
  colorName = zone.color or "gray";
  color = colors.${colorName} or colors.gray;
  internet = zone.internet or "nym";
  socks = zone.socks or null;
  extraApps = map (n: pkgs.${n}) (zone.apps or [ ]);
  socksPort =
    if socks == null then
      null
    else if internet == "i2p" then
      socks + 1000
    else if internet == "tor" || internet == "tor-fallback" then
      socks + 2000
    else
      socks; # nym default
  useProxy = socksPort != null && internet != "none";
in
{
  imports = [ ../../templates/${zone.template}.nix ];

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

  environment.systemPackages = extraApps;

  # Zone color in guest terminal PS1
  environment.etc."profile.d/bunker-zone.sh".text = ''
    export BUNKER_ZONE='${name}'
    export BUNKER_ZONE_COLOR='${colorName}'
    if [ -n "$PS1" ]; then
      printf '\033]11;${color.bg}\007' 2>/dev/null || true
      printf '\033]10;${color.hex}\007' 2>/dev/null || true
      PS1='\[\e[${color.ansi}m\][${name}]\[\e[0m\] \u@\h:\w\$ '
    fi
  '';

  environment.variables = {
    BUNKER_ZONE = name;
    BUNKER_ZONE_COLOR = colorName;
    BUNKER_ZONE_HEX = color.hex;
  }
  // lib.optionalAttrs useProxy {
    ALL_PROXY = "socks5h://10.0.0.1:${toString socksPort}";
    HTTPS_PROXY = "socks5h://10.0.0.1:${toString socksPort}";
    HTTP_PROXY = "socks5h://10.0.0.1:${toString socksPort}";
    NO_PROXY = "10.0.0.0/24,127.0.0.1,localhost";
    BUNKER_INTERNET = internet;
  }
  // lib.optionalAttrs disposable { BUNKER_DISPOSABLE = "1"; }
  // lib.optionalAttrs (internet == "none") { BUNKER_INTERNET = "none"; };

  networking.firewall.extraCommands = lib.mkIf (internet == "none") (
    lib.mkAfter ''
      iptables -P OUTPUT DROP || true
      iptables -A OUTPUT -o lo -j ACCEPT || true
      iptables -A OUTPUT -d 10.0.0.0/24 -j ACCEPT || true
    ''
  );

  environment.etc."bunker/zone.json".text = builtins.toJSON {
    inherit name ip mac socks disposable mem vcpu internet;
    template = zone.template;
    color = colorName;
    usb = zone.usb or [ ];
    apps = zone.apps or [ ];
  };

  services.openssh.enable = true;
}
