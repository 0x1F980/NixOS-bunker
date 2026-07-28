# netVM-related host policy (mixnet runs inside net microVM).
{ ... }:

{
  services.tor.enable = false;

  environment.etc."bunker/nym-routing".text = ''
    Nym/Tor/i2pd run ONLY in the net microVM.
    SOCKS ports on netVM (10.0.0.1):
      personal 1081
      work     1082
      browse   1083
      sdr      1084
    App VMs must not run nym-client or change mixnet config.
    Killswitch: bunker-killswitch enable|disable|status
  '';
}
