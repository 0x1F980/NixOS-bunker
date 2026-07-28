# Storage hardening — no hibernate; prefer no swap (zram via hardware overlay).
{ lib, ... }:

{
  # Never hibernate (plaintext memory risk on disk)
  systemd.sleep.extraConfig = ''
    AllowHibernation=no
    AllowSuspendThenHibernate=no
    AllowHybridSleep=no
  '';

  # Default: no disk swap. Hardware overlays may enable zramSwap.
  swapDevices = lib.mkDefault [ ];

  # Document vault LUKS: mount separately, e.g. /var/lib/bunker/vault
  # fileSystems."/var/lib/bunker/vault" = { device = "/dev/disk/by-uuid/..."; ... };
}
