# Zone registry — source of truth is zones.json (CRUD via: bunker-zone).
# Do not hand-edit this file; edit zones.json or run bunker-zone add|set|rm.
builtins.fromJSON (builtins.readFile ./zones.json)
