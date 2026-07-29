# Deniable (Shufflecake) zone registry — entire hidden VMs.
# CRUD via: bunker-deniable / deniable · service (not hand-edit Nix modules).
# Fields mirror zones.json plus: layer (int), panic (bool).
builtins.fromJSON (builtins.readFile ./deniable-zones.json)
