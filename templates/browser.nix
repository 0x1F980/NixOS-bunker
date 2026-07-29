# Template: browser — minimal ephemeral browsing stack
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    librewolf
    libreoffice
    bleachbit
    firejail
    bubblewrap
    wl-clipboard
  ];

  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      librewolf = {
        executable = "${pkgs.librewolf}/bin/librewolf";
        profile = "${pkgs.firejail}/etc/firejail/librewolf.profile";
      };
    };
  };

  systemd.coredump.enable = false;
}
