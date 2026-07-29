# User-editable zone registry (Qubes-like AppVMs).
#
# Edit THIS file to add/rename zones. Do not fork flake.nix for that.
#
# Templates live in templates/*.nix (like Qubes TemplateVMs).
# System zones (net/usb/vault) are fixed infrastructure — see flake.nix.
#
# Fields:
#   template    — desktop | dev | browser | radio
#   ip          — address on br-bunker (10.0.0.0/24)
#   mac         — unique locally-administered MAC
#   socks       — Nym/Tor SOCKS port on netVM (10.0.0.1); null = no proxy env
#   mem / vcpu  — microVM resources
#   disposable  — true = wipe-friendly (no persistent expectation; use bunker-wipe <zone>)
#
# Examples below are placeholders — rename, delete, or add your own.

{
  personal = {
    template = "desktop";
    ip = "10.0.0.11";
    mac = "02:b0:00:00:00:11";
    socks = 1081;
    mem = 1536;
    vcpu = 2;
    disposable = false;
  };

  work = {
    template = "dev";
    ip = "10.0.0.12";
    mac = "02:b0:00:00:00:12";
    socks = 1082;
    mem = 1920;
    vcpu = 2;
    disposable = false;
  };

  browse = {
    template = "browser";
    ip = "10.0.0.13";
    mac = "02:b0:00:00:00:13";
    socks = 1083;
    mem = 1536;
    vcpu = 2;
    disposable = true;
  };

  radio = {
    template = "radio";
    ip = "10.0.0.14";
    mac = "02:b0:00:00:00:14";
    socks = 1084;
    mem = 1920;
    vcpu = 2;
    disposable = false;
  };

  # Example — uncomment to add another disposable browser slot:
  # throwaway = {
  #   template = "browser";
  #   ip = "10.0.0.15";
  #   mac = "02:b0:00:00:00:15";
  #   socks = 1085;
  #   mem = 1536;
  #   vcpu = 2;
  #   disposable = true;
  # };
}
