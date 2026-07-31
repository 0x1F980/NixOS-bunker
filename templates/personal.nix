# Personal — daily identity, mail, research, media, recon (not inherited by work/slots).
{ pkgs, lib, ... }:

{
  imports = [ ./desktop.nix ];

  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "obsidian" ];

  environment.systemPackages = with pkgs; [
    # Security / crypto / wipe
    kdePackages.kleopatra
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
    # frigate: heavy NVR — enable when you have cameras; keep out of default guest build

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
    kdePackages.marble

    # System / backup (ventoy is unfree+insecure — use host ISO tools instead)
    glances
    mission-center
    zellij
    borgbackup
    restic

    # Voice anonymize (pitch / formant via Easy Effects)
    easyeffects

    # Metadata scrub (Tails UI; uses mat2 under the hood)
    metadata-cleaner
  ];

  services.pcscd.enable = true;
}
