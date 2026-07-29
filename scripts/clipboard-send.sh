#!/usr/bin/env bash
# Compat wrapper — use: bunker-clip send <zone>
exec "$(dirname "$0")/clipboard.sh" send "$@"
