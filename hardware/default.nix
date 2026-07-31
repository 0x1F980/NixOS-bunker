# Pick portable hardware overlay from hostPlatform. Broad KVM, not vendor lock-in.
{
  lib,
  pkgs,
  ...
}:

let
  sys = pkgs.stdenv.hostPlatform.system;
  hw =
    if sys == "aarch64-linux" then
      ./generic-aarch64.nix
    else if sys == "riscv64-linux" then
      ./generic-riscv64.nix
    else
      ./generic-x86_64.nix;
in
{
  imports = [ hw ];
}
