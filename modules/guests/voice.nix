# voiceVM — mic anonymizer broker (1 → many zones), like netVM/usbVM.
# Physical mic / USB headset attach HERE; anonymized stream offered on LAN Pulse (10.0.0.3).
# Engine preference: Chimera (speaker-irreversible) → MorphMic-style sox "anonymous" fallback.
{
  pkgs,
  lib,
  ...
}:

let
  # Realtime-ish anonymizer: Chimera if present, else sox pitch/formant-ish chain
  anonEngine = pkgs.writeShellScriptBin "bunker-voice-anon" ''
    set -euo pipefail
    PRESET="''${1:-anonymous}"
    # Prefer Chimera (cryptographic speaker anonymisation) when installed
    if command -v chimera >/dev/null 2>&1; then
      exec chimera realtime --preset "''${BUNKER_VOICE_CHIMERA_PRESET:-moderate}" "$@"
    fi
    if python3 -c "import chimera" 2>/dev/null; then
      exec python3 - <<'PY'
from chimera.realtime import RealtimeAnonymiser
import os, time
anon = RealtimeAnonymiser(key=os.environ.get("BUNKER_VOICE_KEY", "bunker"), preset=os.environ.get("BUNKER_VOICE_CHIMERA_PRESET", "moderate"))
anon.start()
print("chimera realtime anonymiser running — Ctrl+C to stop", flush=True)
try:
    while True:
        time.sleep(3600)
except KeyboardInterrupt:
    anon.stop()
PY
    fi
    # Fallback: sox + Pulse null sink ( MorphMic-like "anonymous": pitch down + mild distortion )
    command -v sox >/dev/null || { echo "ERROR: need chimera or sox" >&2; exit 1; }
    command -v pactl >/dev/null || { echo "ERROR: need PulseAudio/PipeWire pactl" >&2; exit 1; }
    SINK="bunker-anon"
    pactl load-module module-null-sink sink_name="$SINK" sink_properties=device.description=BunkerAnonMic 2>/dev/null || true
    # Remap monitor to a source apps can pick
    pactl load-module module-remap-source master="''${SINK}.monitor" source_name=bunker-anon-mic source_properties=device.description=BunkerAnonMic 2>/dev/null || true
    SRC="$(pactl get-default-source 2>/dev/null || true)"
    [[ -n "$SRC" ]] || SRC="alsa_input.default"
    echo "voice-anon fallback: sox pitch -500 (anonymous-ish)  $SRC → $SINK"
    echo "Zones: PULSE_SERVER=tcp:10.0.0.3:4713  source=bunker-anon-mic"
    exec sox -t pulse "$SRC" -t pulse "$SINK" pitch -500 highpass 200 bandpass 300 3000 2>/dev/null \
      || exec sox -d -t pulse "$SINK" pitch -500 highpass 200 2>/dev/null \
      || { echo "sox pulse failed — check PipeWire/Pulse on voiceVM" >&2; exit 1; }
  '';

  broker = pkgs.writeShellScriptBin "bunker-voice-broker" ''
    set -euo pipefail
    CMD="''${1:-}"
    case "$CMD" in
      status)
        echo "voiceVM broker 10.0.0.3 — anonymized mic 1→many"
        pactl info 2>/dev/null | head -20 || true
        systemctl is-active bunker-voice-anon.service 2>/dev/null || true
        ;;
      start)
        systemctl start bunker-voice-anon.service
        ;;
      stop)
        systemctl stop bunker-voice-anon.service
        ;;
      *)
        echo "usage: bunker-voice-broker status|start|stop" >&2
        exit 1
        ;;
    esac
  '';
in
{
  microvm.mem = 768;
  microvm.vcpu = 1;

  # Audio stack for mic → anonymizer → LAN Pulse
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
  };
  # TCP Pulse for app zones (auth-anonymous on bunker LAN only — firewall restricts)
  environment.etc."pipewire/pipewire-pulse.conf.d/bunker-tcp.conf".text = ''
    pulse.properties = {
      server.address = [ "unix:native" "tcp:0.0.0.0:4713" ]
      pulse.min.req = 256/48000
    }
  '';

  environment.systemPackages = with pkgs; [
    sox
    pulseaudio # pactl
    usbutils
    anonEngine
    broker
  ];

  systemd.services.bunker-voice-anon = {
    description = "Bunker voice anonymizer (Chimera or sox fallback)";
    wantedBy = [ "multi-user.target" ];
    after = [ "pipewire-pulse.service" "pipewire.service" ];
    serviceConfig = {
      ExecStart = "${anonEngine}/bin/bunker-voice-anon anonymous";
      Restart = "on-failure";
      RestartSec = 3;
      Environment = [
        "BUNKER_VOICE_KEY=bunker"
        "BUNKER_VOICE_CHIMERA_PRESET=moderate"
      ];
    };
  };

  services.openssh.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    22
    4713 # Pulse TCP — anonymized mic to app zones
  ];
  networking.useDHCP = false;

  microvm.interfaces = [
    {
      type = "bridge";
      id = "vm-voice";
      mac = "02:b0:00:00:00:03";
      bridge = "br-bunker";
    }
  ];
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.0.3";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = {
    address = "10.0.0.1";
    interface = "eth0";
  };
  networking.nameservers = [ "10.0.0.1" ];

  users.users.zone.extraGroups = [
    "audio"
    "pipewire"
  ];

  environment.etc."bunker/voice-policy".text = ''
    voiceVM (10.0.0.3) = mic anonymizer broker (1 → many), same idea as net/usb.
    Physical mic attaches to voiceVM only (USB QMP / host policy).
    App zones with voice=anon|chimera use PULSE_SERVER=tcp:10.0.0.3:4713
    Engine: Chimera (preferred) or sox anonymous fallback.
    Defaults TUI: voice · service / bunker-voice
    See docs/voice.md
  '';

  environment.variables.BUNKER_ZONE = "voice";
}
