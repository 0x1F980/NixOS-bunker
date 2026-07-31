# Real Shufflecake invisible zones + panic (host).
# Requires dm_sflc + shufflecake userspace. Bootstrap: bunker-sflc bootstrap
{
  config,
  lib,
  pkgs,
  ...
}:

let
  sflc = config.boot.kernelPackages.shufflecake;
in
{
  boot.extraModulePackages = [ sflc ];
  # Module filename dm-sflc.ko → kernel name dm_sflc
  boot.kernelModules = [
    "dm_mod"
    "dm_sflc"
  ];

  environment.etc."bunker/shufflecake.json".source = ../config/shufflecake.json;

  environment.etc."bunker/panic.conf".text = ''
    PANIC_HASH=057ba03d6c44104863dc7361fe4578965d1887360f90a0895882e58a6248fc86
  '';

  systemd.tmpfiles.rules = [
    "d /run/bunker 0755 root root -"
    "d /run/bunker/xdg 0755 root root -"
    "d /run/bunker/xdg/applications 0755 root root -"
    "d /run/bunker/sflc 0700 root root -"
    "d /mnt/bunker-sflc 0700 root root -"
    "d /var/lib/bunker 0750 root root -"
    "d /var/lib/bunker/file-xfer 0700 root root -"
  ];

  environment.extraInit = ''
    export XDG_DATA_DIRS="/run/bunker/xdg''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
  '';

  environment.systemPackages = [
    sflc.bin
    pkgs.srm
    pkgs.openssl
    pkgs.jq
    pkgs.util-linux
    pkgs.e2fsprogs
    pkgs.openssh
    (pkgs.writeShellScriptBin "bunker-sflc" ''
      exec /etc/bunker/scripts/bunker-sflc.sh "$@"
    '')
    (pkgs.writeShellScriptBin "bunker-panic" ''
      exec /etc/bunker/scripts/bunker-panic.sh "$@"
    '')
  ];
}
