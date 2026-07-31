# Vault — air-gapped secrets (zone.internet = none). No browser, no mail.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    keepassxc
    pass
    gnupg
    kleopatra
    nitrokey-app
    age
    libsodium
    bleachbit
    secure-delete
    btop
    wl-clipboard
  ];
  services.pcscd.enable = true;
  systemd.coredump.enable = false;
}
