#!/usr/bin/env bash
# Qubes-inspired zone CRUD — edits config/zones.json (AppVMs / Disposables).
# Templates live in templates/*.nix (edit via: bunker-zone templates | bunker-template-edit).
# Usage:
#   bunker-zone list
#   bunker-zone show <name>
#   bunker-zone add <name> [--template desktop|iso] [--iso /path.iso] [--kind appvm|disposable|template] …
#   bunker-zone set <name> key=value   # template|internet|color|voice|metadata|iso|boot|disk|…
#   bunker-zone rename <old> <new>
#   bunker-zone rm <name>
#   bunker-zone apps <name> add|rm <pkg>
#   bunker-zone usb  <name> add|rm <vid:pid>
#   bunker-zone templates
#   bunker-zone colors
set -euo pipefail

# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

ROOT="$(bunker_repo_root)"
ZONES_JSON="$(bunker_zones_json)"
COLORS_NIX="$ROOT/config/colors.nix"
TEMPLATES_DIR="$ROOT/templates"
[[ -d "$TEMPLATES_DIR" ]] || TEMPLATES_DIR="$HOME/nixos-bunker/templates"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# //'
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
print(f"{'NAME':12} {'TYPE':11} {'COLOR':8} {'TMPL':10} {'IP':14} {'NET':8} USB/ISO")
for name, c in sorted(z.items()):
    typ = c.get("kind") or ("disposable" if c.get("disposable") else "appvm")
    usb = ",".join(c.get("usb") or []) or "-"
    iso = (c.get("iso") or "").strip()
    extra = f"iso={iso}" if (c.get("template") == "iso" or iso) else usb
    print(f"{name:12} {typ:11} {c.get('color','-'):8} {c.get('template','-'):10} {c.get('ip','-'):14} {c.get('internet','-'):8} {extra}")
PY
}

cmd_templates() {
  echo "NixOS templates (TemplateVM package sets) — edit then: nixos-rebuild switch"
  local d="$TEMPLATES_DIR"
  if [[ ! -d "$d" ]]; then
    echo "No templates dir at $d" >&2
    exit 1
  fi
  for f in "$d"/*.nix; do
    [[ -f "$f" ]] || continue
    local base
    base="$(basename "$f" .nix)"
    echo "  ${base} · template    ($f)"
    echo "    edit: bunker-template-edit $base"
  done
  echo
  echo "ISO / HVM guests: template=iso + iso=/path/to.iso (Tails, other live/install media)"
  echo "  bunker-zone add tails --template iso --iso /var/lib/bunker/isos/tails.iso --disposable"
  echo "  kind=appvm|disposable|template  boot=iso|disk|both  See docs/iso.md"
  echo
  echo "NixOS AppVMs: zones.json \"template\": \"desktop|dev|browser|radio\""
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
  local template="browser" color="red" disposable="false" internet="nym" mem="1536" vcpu="2"
  local iso="" kind="" boot="iso" disk_gb="16"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template)
        template="$2"
        shift 2
        ;;
      --iso)
        iso="$2"
        template="iso"
        shift 2
        ;;
      --kind)
        kind="$2"
        shift 2
        ;;
      --boot)
        boot="$2"
        shift 2
        ;;
      --disk-gb)
        disk_gb="$2"
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
      --vcpu)
        vcpu="$2"
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
  # default internet=nym (i2p|tor|none also valid); ISO live often wants none
  [[ "$internet" == "proxy" ]] && internet="nym"
  if [[ "$template" == "iso" && -z "$iso" ]]; then
    echo "ERROR: --template iso requires --iso /path/to.iso" >&2
    exit 1
  fi
  if [[ "$template" == "iso" && "$mem" == "1536" ]]; then
    mem="2048"
  fi
  if [[ -n "$kind" ]]; then
    case "$kind" in
      disposable) disposable="true" ;;
      appvm|template) disposable="false" ;;
      *)
        echo "ERROR: --kind must be appvm|disposable|template" >&2
        exit 1
        ;;
    esac
  elif [[ "$disposable" == "true" ]]; then
    kind="disposable"
  elif [[ "$template" == "iso" ]]; then
    kind="appvm"
  else
    kind="appvm"
  fi
  need_py
  mapfile -t alloc < <(next_free)
  NAME="$name" TEMPLATE="$template" COLOR="$color" DISP="$disposable" NET="$internet" MEM="$mem" VCPU="$vcpu" \
    IP="${alloc[0]}" MAC="${alloc[1]}" SOCKS="${alloc[2]}" ISO="$iso" KIND="$kind" BOOT="$boot" DISKGB="$disk_gb" \
    py <<'PY'
import json, os
path = os.environ["ZONE_JSON"]
z = json.load(open(path))
n = os.environ["NAME"]
if n in z:
    raise SystemExit(f"zone exists: {n}")
if not n.replace("-", "").replace("_", "").isalnum():
    raise SystemExit("name must be alphanumeric/_/-")
kind = os.environ["KIND"]
entry = {
    "template": os.environ["TEMPLATE"],
    "ip": os.environ["IP"],
    "mac": os.environ["MAC"],
    "socks": int(os.environ["SOCKS"]),
    "mem": int(os.environ["MEM"]),
    "vcpu": int(os.environ["VCPU"]),
    "disposable": os.environ["DISP"] == "true" or kind == "disposable",
    "kind": kind,
    "color": os.environ["COLOR"],
    "internet": os.environ["NET"],
    "usb": [],
    "apps": [],
    "voice": False,
    "metadata": False,
}
iso = os.environ.get("ISO") or ""
if os.environ["TEMPLATE"] == "iso" or iso:
    entry["template"] = "iso"
    entry["iso"] = iso
    entry["boot"] = os.environ.get("BOOT") or "iso"
    entry["diskGb"] = int(os.environ.get("DISKGB") or 16)
    entry["display"] = "gtk"
z[n] = entry
json.dump(z, open(path, "w"), indent=2)
print(f"added {n}: {json.dumps(z[n], indent=2)}")
if entry.get("template") == "iso":
    print("ISO zone: no nixos-rebuild needed for the guest. Start: bunker-zone-start", n)
    print("Refresh GNOME launchers (optional): sudo nixos-rebuild switch --flake .#host")
else:
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
        z[n]["kind"] = "disposable" if z[n][k] else "appvm"
    elif k == "kind":
        if v not in ("appvm", "disposable", "template"):
            raise SystemExit("kind must be appvm|disposable|template")
        z[n][k] = v
        z[n]["disposable"] = v == "disposable"
    elif k in ("template", "ip", "mac", "color", "internet", "iso", "boot", "disk", "display"):
        z[n][k] = v
        if k == "template" and v == "iso" and "iso" not in z[n]:
            z[n]["iso"] = ""
        if k == "iso" and v:
            z[n]["template"] = "iso"
    elif k in ("diskGb", "disk_gb"):
        z[n]["diskGb"] = int(v)
    elif k == "voice":
        # on/off only — engine is global on voiceVM
        truth = {"true", "1", "on", "yes", "anon", "chimera"}
        falsy = {"false", "0", "off", "no", "none", ""}
        vl = v.lower()
        if vl in truth:
            z[n][k] = True
        elif vl in falsy:
            z[n][k] = False
        else:
            raise SystemExit("voice must be on|off (true|false)")
    elif k == "metadata":
        # on/off — ships mat2 (EXIF stripper) into the zone
        truth = {"true", "1", "on", "yes", "mat2"}
        falsy = {"false", "0", "off", "no", "none", ""}
        vl = v.lower()
        if vl in truth:
            z[n][k] = True
        elif vl in falsy:
            z[n][k] = False
        else:
            raise SystemExit("metadata must be on|off (true|false)")
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

cmd_rename() {
  local old="$1" new="$2"
  need_py
  OLD="$old" NEW="$new" py <<'PY'
import json, os, re
path = os.environ["ZONE_JSON"]
z = json.load(open(path))
old, new = os.environ["OLD"], os.environ["NEW"]
if old not in z:
    raise SystemExit(f"unknown zone: {old}")
if not re.fullmatch(r"[A-Za-z0-9_-]+", new):
    raise SystemExit("name must be alphanumeric/_/-")
if new in z:
    raise SystemExit(f"zone exists: {new}")
z[new] = z.pop(old)
json.dump(z, open(path, "w"), indent=2)
print(f"renamed {old} → {new}")
print("Next: sudo nixos-rebuild switch --flake .#host  # icons + NixOS cursor")
print(json.dumps({new: z[new]}, indent=2))
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
    rename | mv) cmd_rename "${1:?old}" "${2:?new}" ;;
    rm | delete) cmd_rm "${1:?name}" ;;
    apps) cmd_apps "${1:?name}" "${2:?add|rm}" "${3:?pkg}" ;;
    usb) cmd_usb "${1:?name}" "${2:?add|rm}" "${3:?vid:pid}" ;;
    templates | template) cmd_templates ;;
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
