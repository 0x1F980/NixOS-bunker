#!/usr/bin/env bash
# Print first-boot checklist + generate hardware-config stub replacement command.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cat <<EOF
== NixOS Bunker first-boot ==

1) Edit YOUR app zones (optional):
     nano $ROOT/config/zones.nix

2) Replace hardware stub (on the target machine):
     sudo nixos-generate-config --show-hardware-config > $ROOT/hosts/bunker/hardware-configuration.nix

3) Set hashed passwords in modules/host-minimal.nix
     mkpasswd -m sha-512
     # replace initialPassword with hashedPassword = "...";

4) Build & switch:
     sudo nixos-rebuild switch --flake $ROOT#host

5) Start infrastructure + one app zone:
     bunker-killswitch enable
     bunker-zone-start net
     # see docs/nym-bootstrap.md
     bunker-zone-start personal   # or your zone name from zones.nix

6) Checks:
     bunker-test-isolation
     bunker-test-isolation --live

Templates:  $ROOT/templates/
Zones file: $ROOT/config/zones.nix
EOF

if [[ "${1:-}" == "--generate-hardware" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: --generate-hardware needs root (sudo $0 --generate-hardware)" >&2
    exit 1
  fi
  nixos-generate-config --show-hardware-config >"$ROOT/hosts/bunker/hardware-configuration.nix"
  echo "Wrote $ROOT/hosts/bunker/hardware-configuration.nix"
fi
