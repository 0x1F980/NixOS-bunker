# Minimal host: GNOME shell + bunker tools + emergency recovery.
{ lib, pkgs, ... }:

let
  bunkerMan = pkgs.writeTextFile {
    name = "bunker-manpage";
    destination = "/share/man/man1/bunker.1";
    text = builtins.readFile ../man/bunker.1;
  };
  wrap =
    name: script:
    pkgs.writeShellScriptBin name ''exec /etc/bunker/scripts/${script} "$@"'';
  wraps = lib.mapAttrsToList wrap {
    bunker-zone-start = "zone-start.sh";
    bunker-usb-attach = "usb-attach.sh";
    bunker-usb-detach = "usb-detach.sh";
    bunker-clip = "clipboard.sh";
    bunker-test-isolation = "test-isolation.sh";
    bunker-killswitch = "killswitch.sh";
    bunker-wipe = "zone-wipe.sh";
    bunker-zone = "bunker-zone.sh";
    bunker-term = "zone-term.sh";
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

  environment.systemPackages =
    with pkgs;
    [
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
      bunkerMan
      (writeShellScriptBin "bunker-help" ''exec ${less}/bin/less /etc/bunker/MANUAL'')
    ]
    ++ wraps;

  services.pcscd.enable = false;
  hardware.nitrokey.enable = false;
}
