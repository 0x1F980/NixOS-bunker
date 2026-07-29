#!/usr/bin/env bash
# Compat wrapper — prefer bunker-wipe <zone>
exec "$(dirname "$0")/zone-wipe.sh" browse "$@"
