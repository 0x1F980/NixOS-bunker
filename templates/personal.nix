# Personal — daily identity, mail, voice, recon/radio (not vault offline knowledge).
# Offline notes/math/office → vault. Radio/SDR here or deniable radio slot.
{ pkgs, lib, ... }:

{
  imports = [ ./desktop.nix ];

  environment.systemPackages = with pkgs; [
    # Security tokens (day-to-day; deep secrets stay in vault)
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

    # Comms (needs netVM SOCKS)
    thunderbird
    neomutt
    element-desktop

    # Maps (may fetch tiles via proxy)
    kdePackages.marble

    # System / backup
    glances
    mission-center
    zellij
    borgbackup
    restic

    # Voice anonymize (pitch / formant via Easy Effects)
    easyeffects
  ];

  services.pcscd.enable = true;
}
