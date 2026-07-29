# Zone registry loader — JSON is the source of truth (CRUD: bunker-zone).
# Keep kind + disposable in sync in zones.json; this file only parses it.
builtins.fromJSON (builtins.readFile ./zones.json)
