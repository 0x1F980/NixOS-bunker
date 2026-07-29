# Build one app-zone NixOS module from a zones.json entry.
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
  templatePath = ../../templates/${zone.template}.nix;
  socks = zone.socks or null;
  disposable = zone.disposable or false;
  mem = zone.mem or 1536;
  vcpu = zone.vcpu or 2;
  ip = zone.ip;
  mac = zone.mac;
  colorName = zone.color or "gray";
  color = colors.${colorName} or colors.gray;
  internet = zone.internet or "proxy";
  extraAppNames = zone.apps or [ ];
  extraApps = map (n: pkgs.${n}) extraAppNames;
  useProxy = internet == "proxy" || internet == "tor-fallback";
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

  # Extra packages declared in zones.json "apps": ["htop", "vim", ...]
  environment.systemPackages = extraApps ++ [
    (pkgs.writeShellScriptBin "bunker-zone-banner" ''
      printf '\033]11;%s\007' '${color.bg}' 2>/dev/null || true
      printf '\033]10;%s\007' '${color.hex}' 2>/dev/null || true
      export PS1='\[\e[${color.ansi}m\][bunker:${name}]\[\e[0m\] \u@\h:\w\$ '
      echo "zone=${name} color=${colorName} internet=${internet}"
    '')
  ];

  # Colorful getty / shell hint
  environment.etc."profile.d/bunker-zone-color.sh".text = ''
    # Qubes-inspired zone label colors
    export BUNKER_ZONE='${name}'
    export BUNKER_ZONE_COLOR='${colorName}'
    export BUNKER_ZONE_HEX='${color.hex}'
    if [ -n "$PS1" ]; then
      printf '\033]11;${color.bg}\007' 2>/dev/null || true
      PS1='\[\e[${color.ansi}m\][${name}]\[\e[0m\] \u@\h:\w\$ '
    fi
  '';

  environment.variables = {
    BUNKER_ZONE = name;
    BUNKER_ZONE_COLOR = colorName;
    BUNKER_ZONE_HEX = color.hex;
  }
  // lib.optionalAttrs (useProxy && socks != null) {
    ALL_PROXY = "socks5h://10.0.0.1:${toString socks}";
    HTTPS_PROXY = "socks5h://10.0.0.1:${toString socks}";
    HTTP_PROXY = "socks5h://10.0.0.1:${toString socks}";
    NO_PROXY = "10.0.0.0/24,127.0.0.1,localhost";
  }
  // lib.optionalAttrs disposable {
    BUNKER_DISPOSABLE = "1";
  }
  // lib.optionalAttrs (internet == "none") {
    BUNKER_INTERNET = "none";
  };

  # internet=none → only talk to bunker LAN (no forward hope without netVM SOCKS anyway)
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
    colorHex = color.hex;
    usb = zone.usb or [ ];
    apps = extraAppNames;
  };

  services.openssh.enable = true;
}
