#!/usr/bin/env bash
# Update ritual — run as admin on the NixOS host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib-arch.sh
source "$ROOT/scripts/lib-arch.sh"
HOST_ATTR="$(bunker_host_flake_attr)"

echo "==> flake update (conscious)"
nix flake update

echo "==> rebuild host (.#$HOST_ATTR)"
sudo nixos-rebuild switch --flake ".#$HOST_ATTR"

echo "==> rebuild/restart guests as needed"
echo "  system: net usb vault"
if [[ -f /etc/bunker/zones.tsv ]]; then
  cut -f1 /etc/bunker/zones.tsv | while read -r z; do
    echo "  app: consider bunker-zone-start $z"
  done
else
  echo "  app zones: see config/zones.json / bunker-zone-start"
fi

echo "Done. Review generations: nixos-rebuild list-generations"
