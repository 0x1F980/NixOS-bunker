# Map uname -m → flake host attr (.#host, .#host-aarch64, …)
# Sourced by first-boot / update-bunker.
bunker_host_flake_attr() {
  case "$(uname -m)" in
    x86_64 | amd64) echo "host" ;;
    i686 | i386) echo "host-i686" ;;
    aarch64 | arm64) echo "host-aarch64" ;;
    armv7l | armv7hl) echo "host-armv7l" ;;
    armv6l) echo "host-armv6l" ;;
    riscv64) echo "host-riscv64" ;;
    riscv32) echo "host-riscv32" ;;
    ppc64le | powerpc64le) echo "host-powerpc64le" ;;
    ppc64 | powerpc64) echo "host-powerpc64" ;;
    ppc | powerpc) echo "host-powerpc" ;;
    mips64el) echo "host-mips64el" ;;
    mipsel | mips) echo "host-mipsel" ;;
    loongarch64) echo "host-loongarch64" ;;
    s390x) echo "host-s390x" ;;
    *)
      # Best effort: host-<uname>
      echo "host-$(uname -m)"
      ;;
  esac
}
