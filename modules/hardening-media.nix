# Media: audio/camera default-deny to guests; PipeWire on host for voice-anon only.
{ lib, pkgs, ... }:

{
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = false;
  };

  # Guests do not get PipeWire socket by default (microvm shares must opt-in).
  # Camera: no pipewire/v4l auto-export to VMs.

  environment.systemPackages = with pkgs; [
    pavucontrol
  ];
}
