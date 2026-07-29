# Shufflecake deniable zone-VMs + panic support (host).
# Public zones: config/zones.json. Hidden whole VMs: config/deniable-zones.json.
# Research-grade: software presence is not deniable. See docs/deniable.md.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  sflcPkg = config.boot.kernelPackages.shufflecake or null;
  sflcBin = if sflcPkg != null then (sflcPkg.bin or sflcPkg) else null;
in
{
  boot.extraModulePackages = lib.mkIf (sflcPkg != null) [ sflcPkg ];
  boot.kernelModules = lib.mkIf (sflcPkg != null) [ "dm-sflc" ];

  environment.etc."bunker/shufflecake.json".source = ../config/shufflecake.json;
  environment.etc."bunker/deniable-zones.json".source = ../config/deniable-zones.json;

  # Default panic passphrase: changeme — replace PANIC_HASH after first boot
  # printf %s 'changeme' | sha256sum
  environment.etc."bunker/panic.conf".text = ''
    PANIC_HASH=057ba03d6c44104863dc7361fe4578965d1887360f90a0895882e58a6248fc86
  '';

  # Runtime XDG path for deniable zone launchers (empty when layers locked)
  systemd.tmpfiles.rules = [
    "d /run/bunker 0755 root root -"
    "d /run/bunker/xdg 0755 root root -"
    "d /run/bunker/xdg/applications 0755 root root -"
    "d /mnt/bunker-sflc 0700 root root -"
    "d /var/lib/bunker/sflc-keys 0700 root root -"
  ];

  environment.extraInit = ''
    export XDG_DATA_DIRS="/run/bunker/xdg''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
  '';

  environment.systemPackages =
    [
      pkgs.secure-delete
      pkgs.openssl
      pkgs.jq
    ]
    ++ lib.optional (sflcBin != null) sflcBin
    ++ [
      (pkgs.writeShellScriptBin "bunker-sflc" ''
        exec /etc/bunker/scripts/bunker-sflc.sh "$@"
      '')
      (pkgs.writeShellScriptBin "bunker-panic" ''
        exec /etc/bunker/scripts/bunker-panic.sh "$@"
      '')
    ];
}
