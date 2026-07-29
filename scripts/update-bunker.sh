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
echo "  system: net usb vault"
if [[ -f /etc/bunker/zones.tsv ]]; then
  cut -f1 /etc/bunker/zones.tsv | while read -r z; do
    echo "  app: consider systemctl restart microvm@$z.service  (or: bunker-zone-start $z)"
  done
else
  echo "  app zones: see config/zones.nix / bunker-zone-start"
fi

echo "==> wipe disposables if needed"
echo "  bunker-wipe browse   # or any disposable from zones.nix"

echo "Done. Review generations: nixos-rebuild list-generations"
