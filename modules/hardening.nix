# Host hardening — one file, durable defaults.
{ lib, pkgs, ... }:

{
  networking.firewall = {
    enable = true;
    allowPing = false;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  boot.tmp.useTmpfs = true;
  boot.kernelParams = [
    "slab_nomerge"
    "page_alloc.shuffle=1"
    "random.trust_cpu=off"
  ];

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.yama.ptrace_scope" = 2;
    "kernel.sysrq" = 0;
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "vm.mmap_rnd_bits" = 32;
  };

  services.avahi.enable = false;
  services.printing.enable = false;
  hardware.bluetooth.enable = false;

  systemd.coredump.enable = false;
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "core";
      type = "hard";
      value = "0";
    }
  ];

  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = false;
    packages = [ pkgs.apparmor-profiles ];
  };

  systemd.sleep.settings.Sleep = {
    AllowHibernation = "no";
    AllowSuspendThenHibernate = "no";
    AllowHybridSleep = "no";
  };

  swapDevices = lib.mkDefault [ ];
}
