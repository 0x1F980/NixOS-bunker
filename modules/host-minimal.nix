# Minimal host: GNOME + microVM tools. No daily user apps (those live in guest VMs).
{ lib, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
  };

  users.mutableUsers = false;

  users.users.bunker = {
    isNormalUser = true;
    description = "Bunker daily operator (no root)";
    extraGroups = [
      "networkmanager"
      "video"
      "audio"
      "input"
    ];
    initialPassword = "changeme-bunker";
  };

  users.users.admin = {
    isNormalUser = true;
    description = "Host admin — TTY / nixos-rebuild only; do NOT use for daily GNOME";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "changeme-admin";
  };

  security.sudo.wheelNeedsPassword = true;
  security.polkit.enable = true;

  environment.etc."bunker/scripts".source = ../scripts;

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    btop
    glances
    mission-center
    zellij
    qemu_kvm
    virtiofsd
    pciutils
    usbutils
    age
    nftables
    sox
    wl-clipboard
    socat
    sshpass
    (writeShellScriptBin "bunker-zone-start" ''
      exec /etc/bunker/scripts/zone-start.sh "$@"
    '')
    (writeShellScriptBin "bunker-usb-attach" ''
      exec /etc/bunker/scripts/usb-attach.sh "$@"
    '')
    (writeShellScriptBin "bunker-usb-detach" ''
      exec /etc/bunker/scripts/usb-detach.sh "$@"
    '')
    (writeShellScriptBin "bunker-clipboard-send" ''
      exec /etc/bunker/scripts/clipboard-send.sh "$@"
    '')
    (writeShellScriptBin "bunker-test-isolation" ''
      exec /etc/bunker/scripts/test-isolation.sh "$@"
    '')
    (writeShellScriptBin "bunker-update" ''
      exec /etc/bunker/scripts/update-bunker.sh "$@"
    '')
    (writeShellScriptBin "bunker-voice-anon" ''
      exec /etc/bunker/scripts/voice-anon.sh "$@"
    '')
    (writeShellScriptBin "bunker-killswitch" ''
      exec /etc/bunker/scripts/killswitch.sh "$@"
    '')
    (writeShellScriptBin "bunker-wipe-browse" ''
      exec /etc/bunker/scripts/zone-wipe-browse.sh "$@"
    '')
  ];

  services.pcscd.enable = true;
  hardware.nitrokey.enable = true;

  documentation.nixos.enable = true;
}
