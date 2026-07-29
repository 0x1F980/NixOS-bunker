#!/usr/bin/env bash
# Qubes-inspired zone CRUD — edits config/zones.json (source of truth).
# Usage:
#   bunker-zone list
#   bunker-zone show <name>
#   bunker-zone add <name> [--template browser] [--color red] [--disposable] [--internet proxy]
#   bunker-zone set <name> key=value [key=value ...]
#   bunker-zone rm <name>
#   bunker-zone apps <name> add|rm <pkg>
#   bunker-zone usb  <name> add|rm <vid:pid>
#   bunker-zone colors
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZONES_JSON="${BUNKER_ZONES_JSON:-$ROOT/config/zones.json}"
COLORS_NIX="$ROOT/config/colors.nix"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# //'
}

need_py() {
  command -v python3 >/dev/null || {
    echo "python3 required for bunker-zone CRUD" >&2
    exit 1
  }
}

py() {
  ZONE_JSON="$ZONES_JSON" python3 - "$@"
}

cmd_list() {
  need_py
  py <<'PY'
import json, os
z = json.load(open(os.environ["ZONE_JSON"]))
print(f"{'NAME':12} {'COLOR':8} {'TMPL':10} {'IP':14} {'SOCKS':5} {'NET':12} {'DISP':5} USB APPS")
for name, c in sorted(z.items()):
    usb = ",".join(c.get("usb") or []) or "-"
    apps = ",".join(c.get("apps") or []) or "-"
    print(f"{name:12} {c.get('color','-'):8} {c.get('template','-'):10} {c.get('ip','-'):14} {str(c.get('socks','-')):5} {c.get('internet','-'):12} {str(c.get('disposable',False)):5} {usb} {apps}")
PY
}

cmd_show() {
  local name="$1"
  need_py
  NAME="$name" py <<'PY'
import json, os
z = json.load(open(os.environ["ZONE_JSON"]))
n = os.environ["NAME"]
if n not in z:
    raise SystemExit(f"unknown zone: {n}")
print(json.dumps({n: z[n]}, indent=2))
PY
}

cmd_colors() {
  echo "Qubes-inspired labels: red orange yellow green blue purple black gray"
  if [[ -f "$COLORS_NIX" ]]; then
    grep -E '^\s+(red|orange|yellow|green|blue|purple|black|gray)' "$COLORS_NIX" | head -20 || true
  fi
}

next_free() {
  need_py
  py <<'PY'
import json, os
z = json.load(open(os.environ["ZONE_JSON"]))
used_ip = {int(c["ip"].split(".")[-1]) for c in z.values() if c.get("ip")}
used_socks = {c["socks"] for c in z.values() if c.get("socks")}
used_mac = {int(c["mac"].split(":")[-1], 16) for c in z.values() if c.get("mac")}
ip = next(i for i in range(11, 250) if i not in used_ip)
socks = next(p for p in range(1081, 1200) if p not in used_socks)
macn = next(i for i in range(0x11, 0xFE) if i not in used_mac)
print(f"10.0.0.{ip}")
print(f"02:b0:00:00:00:{macn:02x}")
print(socks)
PY
}

cmd_add() {
  local name="$1"
  shift
  local template="browser" color="red" disposable="false" internet="proxy" mem="1536" vcpu="2"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template)
        template="$2"
        shift 2
        ;;
      --color)
        color="$2"
        shift 2
        ;;
      --internet)
        internet="$2"
        shift 2
        ;;
      --mem)
        mem="$2"
        shift 2
        ;;
      --disposable)
        disposable="true"
        shift
        ;;
      *)
        echo "unknown flag: $1" >&2
        exit 1
        ;;
    esac
  done
  need_py
  mapfile -t alloc < <(next_free)
  NAME="$name" TEMPLATE="$template" COLOR="$color" DISP="$disposable" NET="$internet" MEM="$mem" VCPU="$vcpu" \
    IP="${alloc[0]}" MAC="${alloc[1]}" SOCKS="${alloc[2]}" py <<'PY'
import json, os
path = os.environ["ZONE_JSON"]
z = json.load(open(path))
n = os.environ["NAME"]
if n in z:
    raise SystemExit(f"zone exists: {n}")
if not n.replace("-", "").replace("_", "").isalnum():
    raise SystemExit("name must be alphanumeric/_/-")
z[n] = {
    "template": os.environ["TEMPLATE"],
    "ip": os.environ["IP"],
    "mac": os.environ["MAC"],
    "socks": int(os.environ["SOCKS"]),
    "mem": int(os.environ["MEM"]),
    "vcpu": int(os.environ["VCPU"]),
    "disposable": os.environ["DISP"] == "true",
    "color": os.environ["COLOR"],
    "internet": os.environ["NET"],
    "usb": [],
    "apps": [],
}
json.dump(z, open(path, "w"), indent=2)
print(f"added {n}: {json.dumps(z[n], indent=2)}")
print("Next: nixos-rebuild switch --flake .#host   # and bunker-zone-start", n)
PY
}

cmd_set() {
  local name="$1"
  shift
  [[ $# -gt 0 ]] || {
    echo "set needs key=value" >&2
    exit 1
  }
  need_py
  NAME="$name" ARGS="$*" py <<'PY'
import json, os
path = os.environ["ZONE_JSON"]
z = json.load(open(path))
n = os.environ["NAME"]
if n not in z:
    raise SystemExit(f"unknown zone: {n}")
bools = {"true": True, "false": False}
for pair in os.environ["ARGS"].split():
    if "=" not in pair:
        raise SystemExit(f"bad pair: {pair}")
    k, v = pair.split("=", 1)
    if k in ("socks", "mem", "vcpu"):
        z[n][k] = int(v)
    elif k == "disposable":
        z[n][k] = bools.get(v.lower(), v.lower() == "1")
    elif k in ("template", "ip", "mac", "color", "internet"):
        z[n][k] = v
    else:
        raise SystemExit(f"unsupported key: {k}")
json.dump(z, open(path, "w"), indent=2)
print(json.dumps({n: z[n]}, indent=2))
PY
}

cmd_rm() {
  local name="$1"
  need_py
  NAME="$name" py <<'PY'
import json, os
path = os.environ["ZONE_JSON"]
z = json.load(open(path))
n = os.environ["NAME"]
if n not in z:
    raise SystemExit(f"unknown zone: {n}")
del z[n]
json.dump(z, open(path, "w"), indent=2)
print(f"removed {n}")
PY
}

cmd_apps() {
  local name="$1" op="$2" pkg="$3"
  need_py
  NAME="$name" OP="$op" PKG="$pkg" FIELD=apps py <<'PY'
import json, os
path = os.environ["ZONE_JSON"]
z = json.load(open(path))
n, op, pkg, field = os.environ["NAME"], os.environ["OP"], os.environ["PKG"], os.environ["FIELD"]
if n not in z:
    raise SystemExit(f"unknown zone: {n}")
lst = list(z[n].get(field) or [])
if op == "add":
    if pkg not in lst:
        lst.append(pkg)
elif op == "rm":
    lst = [x for x in lst if x != pkg]
else:
    raise SystemExit("op must be add|rm")
z[n][field] = lst
json.dump(z, open(path, "w"), indent=2)
print(json.dumps({n: z[n]}, indent=2))
PY
}

cmd_usb() {
  local name="$1" op="$2" dev="$3"
  need_py
  NAME="$name" OP="$op" PKG="$dev" FIELD=usb py <<'PY'
import json, os, re
path = os.environ["ZONE_JSON"]
z = json.load(open(path))
n, op, pkg, field = os.environ["NAME"], os.environ["OP"], os.environ["PKG"], os.environ["FIELD"]
if n not in z:
    raise SystemExit(f"unknown zone: {n}")
if not re.match(r"^[0-9a-fA-F]+:[0-9a-fA-F]+$", pkg):
    raise SystemExit("usb id must be vid:pid hex")
lst = list(z[n].get(field) or [])
if op == "add":
    if pkg not in lst:
        lst.append(pkg)
elif op == "rm":
    lst = [x for x in lst if x != pkg]
else:
    raise SystemExit("op must be add|rm")
z[n][field] = lst
json.dump(z, open(path, "w"), indent=2)
print(json.dumps({n: z[n]}, indent=2))
PY
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    list | ls) cmd_list ;;
    show) cmd_show "${1:?name}" ;;
    add) cmd_add "${1:?name}" "${@:2}" ;;
    set) cmd_set "${1:?name}" "${@:2}" ;;
    rm | delete) cmd_rm "${1:?name}" ;;
    apps) cmd_apps "${1:?name}" "${2:?add|rm}" "${3:?pkg}" ;;
    usb) cmd_usb "${1:?name}" "${2:?add|rm}" "${3:?vid:pid}" ;;
    colors) cmd_colors ;;
    -h | --help | "") usage ;;
    *)
      echo "unknown: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
