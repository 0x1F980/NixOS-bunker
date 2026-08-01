#!/usr/bin/env bash
set -euo pipefail
ROOT="${BUNKER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SRC=/etc/bunker/branding/nixos-bunker.txt
[[ -f $SRC ]] || SRC="$ROOT/branding/nixos-bunker.txt"
exec neofetch --ascii "$SRC" "$@"
