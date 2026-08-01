# Vault — air-gapped (zone.internet = none). Secrets + offline knowledge/math.
# No browser, no mail, no radio/SDR. USB only via usbVM when needed (tokens, etc.).
{ pkgs, lib, ... }:

{
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "obsidian" ];

  environment.systemPackages = with pkgs; [
    # Secrets / crypto
    keepassxc
    pass
    gnupg
    kdePackages.kleopatra
    nitrokey-app
    age
    libsodium

    # Offline math / notes / research
    julia
    obsidian
    zotero
    kiwix-tools
    libreoffice
    stellarium

    # Local AI (models pre-loaded offline; no clearnet in this zone)
    ollama

    # Offline media / scrub / wipe
    kdenlive
    metadata-cleaner
    bleachbit
    secure-delete

    # System
    btop
    wl-clipboard
  ];
  services.pcscd.enable = true;
  systemd.coredump.enable = false;
}
