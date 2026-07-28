# Clipboard policy documentation module (binaries provided by host-minimal).
{ ... }:

{
  # Host → VM only via bunker-clipboard-send.
  # Do not enable SPICE/QEMU guest→host clipboard on microVMs.
  environment.etc."bunker/clipboard-policy".text = ''
    POLICY: one-way host → VM only.
    - Use: bunker-clipboard-send <vm> [text|-]
    - Never paste from guest into host clipboard tools.
    - VM↔VM: use explicit mediated copy; do not route via host clipboard.
  '';
}
