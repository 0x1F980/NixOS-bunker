# vault — crypto only, no network interface
{ pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    keepassxc
    pass
    gnupg
    age
    kleopatra
  ];

  programs.gnupg.agent.enable = true;

  microvm.mem = 768;
  microvm.vcpu = 1;

  # No NIC — air-gapped at VM level
  microvm.interfaces = lib.mkForce [ ];

  networking.useDHCP = false;
  networking.interfaces = lib.mkForce { };
  networking.defaultGateway = lib.mkForce null;
  networking.nameservers = lib.mkForce [ ];
  networking.proxy = lib.mkForce { };

  environment.variables.BUNKER_ZONE = "vault";

  # No browsers / chat / mail
  systemd.coredump.enable = false;
  services.openssh.enable = false;
}
