# Template: dev — desktop + development / AI tools
{ pkgs, ... }:

{
  imports = [ ./desktop.nix ];

  environment.systemPackages = with pkgs; [
    vscodium
    ollama
    gcc
    clang
    kdenlive
    libsodium
  ];
}
