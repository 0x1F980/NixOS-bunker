#!/usr/bin/env bash
# Update ritual — run as admin on the NixOS host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> flake update (conscious)"
nix flake update

echo "==> rebuild host"
sudo nixos-rebuild switch --flake .#host

echo "==> rebuild/restart guests as needed"
for z in net usb personal work browse vault sdr; do
  echo "  - consider: systemctl restart microvm@$z.service"
done

echo "==> wipe browse if throwaway session ended"
echo "  bunker-wipe-browse"

echo "Done. Review generations: nixos-rebuild list-generations"
