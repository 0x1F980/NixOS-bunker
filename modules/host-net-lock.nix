# Host clearnet lockdown — Qubes-like: host is not a browsing/egress domain.
# Default: host may talk to lo + bunker LAN (10.0.0.0/24) only.
# Temporary WAN: bunker-host-net allow   (for nixos-rebuild / updates)
#                  bunker-host-net lock
{
  lib,
  pkgs,
  ...
}:

let
  hostLockNft = pkgs.writeText "bunker-host-net-lock.nft" ''
    table inet bunker_host {
      chain output {
        type filter hook output priority filter; policy drop;
        oifname "lo" accept
        ip daddr 127.0.0.0/8 accept
        ip daddr 10.0.0.0/24 accept
        ip6 daddr ::1 accept
        ct state established,related accept
        udp dport 67 accept
        udp sport 68 accept
      }
    }
  '';
  applyLock = pkgs.writeShellScript "bunker-host-net-lock-apply" ''
    set -euo pipefail
    ${pkgs.nftables}/bin/nft delete table inet bunker_host 2>/dev/null || true
    ${pkgs.nftables}/bin/nft -f ${hostLockNft}
  '';
  removeLock = pkgs.writeShellScript "bunker-host-net-lock-remove" ''
    ${pkgs.nftables}/bin/nft delete table inet bunker_host 2>/dev/null || true
  '';
in
{
  networking.nameservers = lib.mkDefault [ "10.0.0.1" ];
  networking.enableIPv6 = lib.mkDefault false;

  systemd.services.bunker-host-net-lock = {
    description = "Lock host clearnet (Qubes-like dom0)";
    after = [ "network-pre.target" ];
    before = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${applyLock}";
      ExecStop = "${removeLock}";
    };
  };

  # Guest WAN killswitch on by default (app zones → only via netVM)
  systemd.services.bunker-killswitch = {
    description = "Block app-guest WAN; allow vm-net egress";
    after = [
      "network-online.target"
      "bunker-bridge-up.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeShellScript "bunker-killswitch-on" ''
        exec /etc/bunker/scripts/killswitch.sh enable
      ''}";
      ExecStop = "${pkgs.writeShellScript "bunker-killswitch-off" ''
        exec /etc/bunker/scripts/killswitch.sh disable
      ''}";
    };
  };

  environment.etc."bunker/host-net".text = ''
    DEFAULT: host clearnet LOCKED (lo + 10.0.0.0/24 only).
    Updates:  sudo bunker-host-net allow
              (netVM up for DNS, or set a temporary nameserver)
              sudo nixos-rebuild switch --flake .#host
              sudo bunker-host-net lock
    Guests:   killswitch ON — app WAN only via netVM.
  '';
}
