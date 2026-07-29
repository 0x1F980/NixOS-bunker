# vault — air-gapped storage AppVM: crypto tools only, no NIC (lib.mkForce []).
{ pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    keepassxc
    pass
    gnupg
    age
    kdePackages.kleopatra
  ];

  programs.gnupg.agent.enable = true;

  microvm.mem = 768;
  microvm.vcpu = 1;

  # No NIC — air-gapped at VM level
  microvm.interfaces = lib.mkForce [ ];

  networking.useDHCP = false;
  networking.useNetworkd = lib.mkForce false;
  networking.interfaces = lib.mkForce { };
  networking.defaultGateway = lib.mkForce null;
  networking.nameservers = lib.mkForce [ ];
  networking.proxy = lib.mkForce { };

  environment.variables.BUNKER_ZONE = "vault";

  # No browsers / chat / mail
  systemd.coredump.enable = false;
  services.openssh.enable = lib.mkForce false;
}
