# QEMU/ISO support for every host arch — not x86-only.
{
  lib,
  pkgs,
  ...
}:

let
  arch = pkgs.stdenv.hostPlatform.qemuArch;
  qemuPkg = pkgs.qemu_kvm;
  qemuBin =
    if builtins.pathExists "${qemuPkg}/bin/qemu-kvm" then
      "${qemuPkg}/bin/qemu-kvm"
    else if arch == "aarch64" then
      "${qemuPkg}/bin/qemu-system-aarch64"
    else if arch == "riscv64" then
      "${pkgs.qemu}/bin/qemu-system-riscv64"
    else
      "${qemuPkg}/bin/qemu-system-x86_64";
in
{
  environment.etc."bunker/qemu.env".text = ''
    ARCH=${arch}
    QEMU_BIN=${qemuBin}
  '';

  # qemu_kvm = native; qemu = foreign-arch ISO via TCG when needed
  environment.systemPackages = [
    qemuPkg
    pkgs.qemu
  ]
  ++ lib.optionals (pkgs.stdenv.hostPlatform.isx86_64 || pkgs.stdenv.hostPlatform.isAarch64) [
    pkgs.OVMF
  ];
}
