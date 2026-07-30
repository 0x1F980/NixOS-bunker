# Minimal host: GNOME shell + bunker tools + emergency disk recovery.
# Daily apps live in zones.
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
  services.udisks2.enable = true;

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

  services.openssh = {
    enable = lib.mkForce true;
    startWhenNeeded = lib.mkForce false;
    openFirewall = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PermitRootLogin = "yes";
    };
  };
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  # bunker / changeme-bunker · admin|root / changeme-admin
  users.users.bunker = {
    isNormalUser = true;
    description = "Bunker daily operator";
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
    description = "Host admin";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPassword = "$6$byfl3va1hI3gFNNW$8jBB1q/8Iu2nYdQZCLtdAZt/qoBM9MoS.SJRAdr8eTOmYyhTuxu7g4l7e/en6yhE1NyuJ8Tl9lhjT54gWKg6d0";
  };

  users.users.root.hashedPassword = "$6$byfl3va1hI3gFNNW$8jBB1q/8Iu2nYdQZCLtdAZt/qoBM9MoS.SJRAdr8eTOmYyhTuxu7g4l7e/en6yhE1NyuJ8Tl9lhjT54gWKg6d0";

  security.sudo.wheelNeedsPassword = true;
  security.polkit.enable = true;

  environment.etc."bunker/scripts".source = ../scripts;
  environment.etc."bunker/MANUAL".source = ../docs/MANUAL.txt;

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
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
    gnome-console
    gnome-control-center
    gnome-disk-utility
    gnome-text-editor
    gnome-logs
    nautilus
    cryptsetup
    parted
    smartmontools
    e2fsprogs
    dosfstools
    rsync
    mat2
    bunkerMan
    (writeShellScriptBin "bunker-mat" ''
      exec ${pkgs.mat2}/bin/mat2 --inplace "$@"
    '')
    (writeShellScriptBin "bunker-help" ''
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
    (writeShellScriptBin "bunker-killswitch" ''
      exec /etc/bunker/scripts/killswitch.sh "$@"
    '')
    (writeShellScriptBin "bunker-wipe" ''
      exec /etc/bunker/scripts/zone-wipe.sh "$@"
    '')
    (writeShellScriptBin "bunker-zone" ''
      exec /etc/bunker/scripts/bunker-zone.sh "$@"
    '')
    (writeShellScriptBin "bunker-term" ''
      exec /etc/bunker/scripts/zone-term.sh "$@"
    '')
  ];

  services.pcscd.enable = false;
  hardware.nitrokey.enable = false;
}
