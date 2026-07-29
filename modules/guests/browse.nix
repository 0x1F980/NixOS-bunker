# browse zone — ephemeral throwaway
{ pkgs, lib, ... }:

{
  # Minimal packages — not full template
  environment.systemPackages = with pkgs; [
    librewolf
    libreoffice
    bleachbit
    firejail
    bubblewrap
  ];

  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      librewolf = {
        executable = "${pkgs.librewolf}/bin/librewolf";
        profile = "${pkgs.firejail}/etc/firejail/librewolf.profile";
      };
    };
  };

  microvm.mem = 1536;
  microvm.interfaces = [
    {
      type = "bridge";
      id = "vm-browse";
      mac = "02:b0:00:00:00:13";
      bridge = "br-bunker";
    }
  ];

  networking.useDHCP = false;
  # Ephemeral: prefer tmpfs root overlays when using microvm writableStoreOverlay / volumes
  # Wipe script resets volume via host scripts/zone-wipe-browse.sh

  environment.variables = {
    BUNKER_ZONE = "browse";
    ALL_PROXY = "socks5h://10.0.0.1:1083";
    HTTPS_PROXY = "socks5h://10.0.0.1:1083";
    HTTP_PROXY = "socks5h://10.0.0.1:1083";
  };

  networking.defaultGateway = lib.mkDefault {
    address = "10.0.0.1";
    interface = "eth0";
  };
  networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [
    {
      address = "10.0.0.13";
      prefixLength = 24;
    }
  ];

  networking.nameservers = [ "10.0.0.1" ];
  # SSH kept for host→guest clipboard only (password zone; no guest→host clip)
  services.openssh.enable = true;
  systemd.coredump.enable = false;
}
