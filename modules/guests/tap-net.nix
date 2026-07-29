# Shared bridge interface helper for bunker guests on br-bunker.
# Import and set id/mac per zone; or inline microvm.interfaces in the zone file.
{ lib, ... }:

{
  # Convention (also documented in modules/microvm-network.nix):
  #   type = "bridge"; bridge = "br-bunker"; id = "vm-<zone>"; mac = "02:b0:…"
  # netVM additionally attaches type = "user" for WAN/mixnet.
  networking.useDHCP = lib.mkDefault false;
  networking.nameservers = lib.mkDefault [ "10.0.0.1" ];
}
