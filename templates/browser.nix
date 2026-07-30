# Browser disposable — LibreWolf + mat2.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    librewolf
    bleachbit
    mat2
    wl-clipboard
    (writeShellScriptBin "bunker-mat" ''exec ${mat2}/bin/mat2 --inplace "$@"'')
  ];
  systemd.coredump.enable = false;
}
