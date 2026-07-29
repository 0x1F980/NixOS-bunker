#!/usr/bin/env bash
# Print first-boot checklist; picks host flake attr from CPU (all nixpkgs Linux ISAs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-arch.sh
source "$ROOT/scripts/lib-arch.sh"

HOST_ATTR="$(bunker_host_flake_attr)"
ARCH="$(uname -m)"

cat <<EOF
== NixOS Bunker first-boot ==
CPU arch: $ARCH  →  flake attr: .#$HOST_ATTR
(Ceiling = every Linux ISA in nixpkgs — docs/portability.md)

1) Edit YOUR app zones (optional):
     nano $ROOT/config/zones.json
     bunker-zone list

2) Replace hardware stub (on the target machine):
     sudo nixos-generate-config --show-hardware-config > $ROOT/hosts/bunker/hardware-configuration.nix

3) Set hashed passwords in modules/host-minimal.nix
     mkpasswd -m sha-512

4) Build & switch (native ISA):
     sudo nixos-rebuild switch --flake $ROOT#$HOST_ATTR

5) Start infrastructure + one app zone:
     bunker-killswitch enable
     bunker-zone-start net
     bunker-zone-start personal

6) Checks:
     bunker-test-isolation
     bunker-test-isolation --live

Zones: nix run .#zone-<name>   # auto = this CPU
EOF

if [[ "${1:-}" == "--generate-hardware" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: --generate-hardware needs root" >&2
    exit 1
  fi
  nixos-generate-config --show-hardware-config >"$ROOT/hosts/bunker/hardware-configuration.nix"
  echo "Wrote $ROOT/hosts/bunker/hardware-configuration.nix"
fi
