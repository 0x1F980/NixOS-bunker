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
  # Port offsets on netVM (see modules/guests/net.nix / docs/egress.md)
  socksOffset =
    {
      nym = 0;
      i2p = 1000;
      tor = 2000;
      "nym-tor" = 3000;
      "i2p-tor" = 4000;
      "tor-nym" = 5000;
      "i2p-nym" = 6000;
    }
    .${internet} or null;
  socksPort =
    if socks == null || internet == "none" || socksOffset == null then
      null
    else
      socks + socksOffset;
  useProxy = socksPort != null;
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
  # NO default gateway — clearnet has nowhere to route. SOCKS/DNS are on-link 10.0.0.1.
  networking.defaultGateway = lib.mkForce null;
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

  # HARD egress: apps cannot clearnet even if they ignore ALL_PROXY.
  networking.firewall.extraCommands = lib.mkAfter (
    if internet == "none" then
      ''
        iptables -P OUTPUT DROP || true
        iptables -F OUTPUT || true
        iptables -A OUTPUT -o lo -j ACCEPT || true
        iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
        iptables -A OUTPUT -d 10.0.0.0/24 -j ACCEPT || true
      ''
    else if useProxy then
      ''
        iptables -P OUTPUT DROP || true
        iptables -F OUTPUT || true
        iptables -A OUTPUT -o lo -j ACCEPT || true
        iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
        # Only this zone's SOCKS on netVM + Tor DNS + usbVM
        iptables -A OUTPUT -d 10.0.0.1 -p tcp --dport ${toString socksPort} -j ACCEPT || true
        iptables -A OUTPUT -d 10.0.0.1 -p udp --dport 53 -j ACCEPT || true
        iptables -A OUTPUT -d 10.0.0.1 -p tcp --dport 53 -j ACCEPT || true
        iptables -A OUTPUT -d 10.0.0.2 -j ACCEPT || true
      ''
    else
      ''
        iptables -P OUTPUT DROP || true
        iptables -F OUTPUT || true
        iptables -A OUTPUT -o lo -j ACCEPT || true
        iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
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
