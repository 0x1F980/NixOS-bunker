# Minimal host: GNOME shell + zone launchers + VM ops. No daily apps (those are in VMs).
{ lib, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Absolutely no GNOME "app store" junk on host
  services.gnome.core-apps.enable = false;
  services.gnome.core-developer-tools.enable = false;
  services.gnome.games.enable = false;
  services.gnome.gnome-browser-connector.enable = false;
  services.gnome.gnome-initial-setup.enable = false;
  services.gnome.gnome-remote-desktop.enable = false;
  services.gnome.gnome-user-share.enable = false;
  services.gnome.rygel.enable = false;
  services.gnome.sushi.enable = false;

  environment.gnome.excludePackages = with pkgs; [
    baobab
    cheese
    epiphany
    evince
    geary
    gnome-calculator
    gnome-calendar
    gnome-characters
    gnome-clocks
    gnome-contacts
    gnome-disk-utility
    gnome-font-viewer
    gnome-logs
    gnome-maps
    gnome-music
    gnome-photos
    gnome-software
    gnome-text-editor
    gnome-tour
    gnome-user-docs
    gnome-weather
    gnome-connections
    loupe
    nautilus
    orca
    simple-scan
    snapshot
    totem
    yelp
  ];

  # No NixOS manual / docs in menus
  documentation.enable = false;
  documentation.nixos.enable = false;
  documentation.doc.enable = false;
  documentation.info.enable = false;
  documentation.man.enable = false;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
  };

  users.mutableUsers = false;

  # bunker/bunker  admin/admin  root/admin — change with passwd
  users.users.bunker = {
    isNormalUser = true;
    description = "Bunker daily operator (no root)";
    extraGroups = [
      "networkmanager"
      "video"
      "audio"
      "input"
    ];
    hashedPassword = "$6$rUWh1MatsoP3pIEp$lCI5G0SE5Gvip8gDu5tYLax2FMFYw0IAyq4fTPYpCeeRMGK32IbgLWZdMXPhJPm3/yPQxYQc7KyE4h2EV67tW/";
  };

  users.users.admin = {
    isNormalUser = true;
    description = "Host admin — TTY / nixos-rebuild only";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPassword = "$6$SLamUKVV.Ht9pdyf$Wf96/D4CFCrnwFeA/DvhtbEC300Rub3rjuKmAuXqHqaDEb5m7vtCft6DQbagyk/qvmwLTFJgmARGqxWI2bE3q1";
  };

  users.users.root.hashedPassword = "$6$SLamUKVV.Ht9pdyf$Wf96/D4CFCrnwFeA/DvhtbEC300Rub3rjuKmAuXqHqaDEb5m7vtCft6DQbagyk/qvmwLTFJgmARGqxWI2bE3q1";

  # Drop emergency autologin now that login works
  # services.getty.autologinUser = "admin";

  security.sudo.wheelNeedsPassword = true;
  security.polkit.enable = true;

  environment.etc."bunker/scripts".source = ../scripts;

  # Host packages: zone/VM ops + tiny offline tools only (no consumer apps)
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    btop
    qemu_kvm
    virtiofsd
    pciutils
    usbutils
    nftables
    wl-clipboard
    socat
    sshpass
    gnome-console # terminal for bunker-* commands
    gnome-control-center # Wi‑Fi / display / power only
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
      exec /etc/bunker/scripts/clipboard.sh send "$@"
    '')
    (writeShellScriptBin "bunker-clip" ''
      exec /etc/bunker/scripts/clipboard.sh "$@"
    '')
    (writeShellScriptBin "bunker-test-isolation" ''
      exec /etc/bunker/scripts/test-isolation.sh "$@"
    '')
    (writeShellScriptBin "bunker-update" ''
      exec /etc/bunker/scripts/update-bunker.sh "$@"
    '')
    (writeShellScriptBin "bunker-killswitch" ''
      exec /etc/bunker/scripts/killswitch.sh "$@"
    '')
    (writeShellScriptBin "bunker-wipe" ''
      exec /etc/bunker/scripts/zone-wipe.sh "$@"
    '')
    (writeShellScriptBin "bunker-wipe-browse" ''
      exec /etc/bunker/scripts/zone-wipe-browse.sh "$@"
    '')
    (writeShellScriptBin "bunker-first-boot" ''
      exec /etc/bunker/scripts/first-boot.sh "$@"
    '')
    (writeShellScriptBin "bunker-zone" ''
      exec /etc/bunker/scripts/bunker-zone.sh "$@"
    '')
    (writeShellScriptBin "bunker-term" ''
      exec /etc/bunker/scripts/zone-term.sh "$@"
    '')
  ];

  # No smartcard/nitrokey stack on host — use a zone if needed
  services.pcscd.enable = false;
  hardware.nitrokey.enable = false;
}
