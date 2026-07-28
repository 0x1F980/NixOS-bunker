#!/usr/bin/env bash
# Wipe browse zone state (ephemeral throwaway).
set -euo pipefail

BROWSE_DATA="${BUNKER_BROWSE_DATA:-/var/lib/microvms/browse}"
echo "==> wiping browse data at $BROWSE_DATA"
systemctl stop microvm@browse.service 2>/dev/null || true
rm -rf "${BROWSE_DATA:?}/"*
echo "browse wiped. Start again with: bunker-zone-start browse"
