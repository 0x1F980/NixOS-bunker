# Minimal host (dom0-like): terminal, settings, qube launchers, bunker-* tools,
# plus emergency disk/backup GUIs for when VMs are unavailable — nothing else daily.
# Daily apps live in AppVMs / Disposables / Templates (see modules/zones-ui.nix).
{ lib, pkgs, ... }:

let
  bunkerMan = pkgs.writeTextFile {
    name = "bunker-manpage";
    destination = "/share/man/man1/bunker.1";
    text = builtins.readFile ../man/bunker.1;
  };
in
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.udisks2.enable = true; # Disks / GParted / Files mounts

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

  # Keep emergency recovery apps; strip consumer GNOME.
  # KEPT (host menu): gnome-disk-utility, nautilus, baobab, gnome-text-editor, gnome-logs
  environment.gnome.excludePackages = with pkgs; [
    cheese
    epiphany
    evince
    geary
    gnome-calculator
    gnome-calendar
    gnome-characters
    gnome-clocks
    gnome-contacts
    gnome-font-viewer
    gnome-maps
    gnome-music
    gnome-photos
    gnome-software
    gnome-tour
    gnome-user-docs
    gnome-weather
    gnome-connections
    loupe
    orca
    simple-scan
    snapshot
    totem
    yelp
  ];

  # man bunker only — no huge NixOS doc tree in menus
  documentation.enable = true;
  documentation.man.enable = true;
  documentation.nixos.enable = false;
  documentation.doc.enable = false;
  documentation.info.enable = false;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
  };

  users.mutableUsers = false;

  # Defaults after flake switch (change with passwd):
  #   bunker / changeme-bunker
  #   admin  / changeme-admin
  #   root   / changeme-admin
  users.users.bunker = {
    isNormalUser = true;
    description = "Bunker daily operator (no root)";
    extraGroups = [
      "networkmanager"
      "video"
      "audio"
      "input"
    ];
    hashedPassword = "$6$yobMn1FbbF3w0BBL$hENazauAiBWxmQ7g.k2ci8RuFr5NKtk.qHC/2AM1YkDFATF2xCI8JvRXNxkS2a.BjqwzUpIODvqcAjQzaTwRt0";
  };

  users.users.admin = {
    isNormalUser = true;
    description = "Host admin — TTY / nixos-rebuild only";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPassword = "$6$byfl3va1hI3gFNNW$8jBB1q/8Iu2nYdQZCLtdAZt/qoBM9MoS.SJRAdr8eTOmYyhTuxu7g4l7e/en6yhE1NyuJ8Tl9lhjT54gWKg6d0";
  };

  users.users.root.hashedPassword = "$6$byfl3va1hI3gFNNW$8jBB1q/8Iu2nYdQZCLtdAZt/qoBM9MoS.SJRAdr8eTOmYyhTuxu7g4l7e/en6yhE1NyuJ8Tl9lhjT54gWKg6d0";

  # Drop emergency autologin now that login works
  # services.getty.autologinUser = "admin";

  security.sudo.wheelNeedsPassword = true;
  security.polkit.enable = true;

  environment.etc."bunker/scripts".source = ../scripts;
  environment.etc."bunker/MANUAL".source = ../docs/MANUAL.txt;

  # Host packages: zone ops + emergency disk/backup (no consumer apps)
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    btop
    jq
    tmux
    qemu_kvm
    virtiofsd
    pciutils
    usbutils
    nftables
    wl-clipboard
    socat
    sshpass
    # Emergency GUI (also appear in GNOME app grid)
    gnome-console
    gnome-control-center
    gnome-disk-utility
    gnome-text-editor
    gnome-logs
    nautilus
    baobab
    gparted
    # Emergency CLI — disk / FS / LUKS / backup / recovery
    cryptsetup
    parted
    gptfdisk
    smartmontools
    nvme-cli
    hdparm
    lvm2
    e2fsprogs
    btrfs-progs
    xfsprogs
    dosfstools
    ntfs3g
    ddrescue
    testdisk
    rsync
    borgbackup
    # Emergency metadata strip (also in zones when metadata=true)
    mat2
    (writeShellScriptBin "bunker-mat" ''
      exec ${pkgs.mat2}/bin/mat2 --inplace "$@"
    '')
    bunkerMan
    (writeShellScriptBin "bunker-help" ''
      set -euo pipefail
      if command -v man >/dev/null 2>&1 && man -w bunker >/dev/null 2>&1; then
        exec man bunker "$@"
      fi
      exec ${pkgs.less}/bin/less /etc/bunker/MANUAL
    '')
    (writeShellScriptBin "bunker-zone-start" ''
      exec /etc/bunker/scripts/zone-start.sh "$@"
    '')
    (writeShellScriptBin "bunker-usb-attach" ''
      exec /etc/bunker/scripts/usb-attach.sh "$@"
    '')
    (writeShellScriptBin "bunker-usb-detach" ''
      exec /etc/bunker/scripts/usb-detach.sh "$@"
    '')
    (writeShellScriptBin "bunker-voice-attach" ''
      exec /etc/bunker/scripts/voice-attach.sh "$@"
    '')
    (writeShellScriptBin "bunker-voice-detach" ''
      exec /etc/bunker/scripts/voice-detach.sh "$@"
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
