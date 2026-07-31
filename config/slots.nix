# Anonymous deniable guest slots (d1..dN) — not secret zone names.
builtins.fromJSON (builtins.readFile ./slots.json)
