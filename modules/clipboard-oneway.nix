# Mediated clipboard TTL only.
{ lib, ... }:

{
  environment.etc."bunker/clipboard.conf".text = ''
    TTL=30
  '';
  environment.variables.BUNKER_CLIP_TTL = lib.mkDefault "30";
}
