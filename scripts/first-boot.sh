#!/usr/bin/env bash
# Print first-boot checklist; auto-detects x86_64 vs aarch64 host flake attr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

host_flake_attr() {
  case "$(uname -m)" in
    aarch64 | arm64) echo "host-aarch64" ;;
    riscv64) echo "host-riscv64" ;;
    *) echo "host" ;;
  esac
}

HOST_ATTR="$(host_flake_attr)"
ARCH="$(uname -m)"

cat <<EOF
== NixOS Bunker first-boot ==
CPU arch: $ARCH  →  flake attr: .#$HOST_ATTR
(Also see docs/portability.md)

1) Edit YOUR app zones (optional):
     nano $ROOT/config/zones.json
     bunker-zone list

2) Replace hardware stub (on the target machine):
     sudo nixos-generate-config --show-hardware-config > $ROOT/hosts/bunker/hardware-configuration.nix

3) Set hashed passwords in modules/host-minimal.nix
     mkpasswd -m sha-512
     # replace initialPassword with hashedPassword = "...";

4) Build & switch (native ISA — same machine you boot):
     sudo nixos-rebuild switch --flake $ROOT#$HOST_ATTR

5) Start infrastructure + one app zone:
     bunker-killswitch enable
     bunker-zone-start net
     # see docs/nym-bootstrap.md
     bunker-zone-start personal

6) Checks:
     bunker-test-isolation
     bunker-test-isolation --live

Zones auto-pick arch:  nix run .#zone-<name>
Templates:  $ROOT/templates/
Zones file: $ROOT/config/zones.json
EOF

if [[ "${1:-}" == "--generate-hardware" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: --generate-hardware needs root (sudo $0 --generate-hardware)" >&2
    exit 1
  fi
  nixos-generate-config --show-hardware-config >"$ROOT/hosts/bunker/hardware-configuration.nix"
  echo "Wrote $ROOT/hosts/bunker/hardware-configuration.nix"
fi
