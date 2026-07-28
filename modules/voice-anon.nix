# Voice anonymizer — sox-based helper (bunker-voice-anon from host-minimal).
{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.sox ];
  environment.etc."bunker/voice-anon".text = ''
    Toggle docs: bunker-voice-anon on|off|once
    Pitch-shift demo uses sox. Persistent PipeWire graphs are per-machine.
    Audio/camera to guests remain default-deny (no PW socket share).
  '';
}
