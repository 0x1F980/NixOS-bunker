# Personal — daily identity, mail, research, media, recon (not inherited by work/radio).
{ pkgs, lib, ... }:

{
  imports = [ ./desktop.nix ];

  # Obsidian is unfree.
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "obsidian" ];

  environment.systemPackages = with pkgs; [
    # Security / crypto / wipe
    kleopatra
    nitrokey-app
    clamav
    libsodium
    secure-delete

    # Net / recon / radio / mesh (USB via usbVM when needed)
    wireshark
    sigdigger
    sdrpp
    urh
    hackrf
    rtl_433
    python3Packages.meshtastic
    frigate

    # Comms
    thunderbird
    neomutt
    element-desktop

    # Dev / AI
    ollama

    # Notes / research / offline knowledge
    obsidian
    zotero
    kiwix-tools

    # Media / office / maps
    kdenlive
    libreoffice
    stellarium
    marble

    # System / backup / USB tools
    glances
    mission-center
    zellij
    borgbackup
    restic
    ventoy-full

    # Voice anonymize (pitch / formant via Easy Effects)
    easyeffects

    # Metadata scrub (Tails UI; uses mat2 under the hood)
    metadata-cleaner
  ];

  # Nitrokey / smartcard
  services.pcscd.enable = true;
}
