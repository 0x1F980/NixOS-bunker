#!/usr/bin/env bash
# Zone CRUD — edits config/zones.json
# Usage: bunker-zone list|show|add|set|rename|rm|apps|usb|templates|colors
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"
ZONES_JSON="$(bunker_public_zones_json)"
ROOT="$(bunker_repo_root)"
TPL="$ROOT/templates"
[[ -d "$TPL" ]] || TPL="$HOME/NixOS-bunker/templates"
export ZONE_JSON="$ZONES_JSON"
py() { python3 - "$@"; }

case "${1:-}" in
  list|ls) py <<'PY'
import json,os
z=json.load(open(os.environ["ZONE_JSON"]))
print(f"{'NAME':12} {'TYPE':11} {'COLOR':7} {'TMPL':8} {'IP':14} {'NET':6} EXTRA")
for n,c in sorted(z.items()):
 t=c.get("kind") or ("disposable" if c.get("disposable") else "appvm")
 iso=(c.get("iso") or "").strip()
 x=f"iso={iso}" if (c.get("template")=="iso" or iso) else ",".join(c.get("usb") or []) or "-"
 print(f"{n:12} {t:11} {c.get('color','-'):7} {c.get('template','-'):8} {c.get('ip','-'):14} {c.get('internet','-'):6} {x}")
PY
  ;;
  show) NAME="${2:?}" py <<'PY'
import json,os
z=json.load(open(os.environ["ZONE_JSON"]));n=os.environ["NAME"]
assert n in z, n; print(json.dumps({n:z[n]},indent=2))
PY
  ;;
  templates|template)
    for f in "$TPL"/*.nix; do [[ -f "$f" ]] && echo "  $(basename "$f" .nix)"; done
    echo "ISO: bunker-zone add tails --template iso --iso /path.iso --disposable"
    ;;
  colors)
    echo "Colors: red orange yellow green blue purple black gray"
    echo "Set: bunker-zone set <zone> color=blue"
    echo "(Host icon + zone terminal PS1; rebuild after color/rename)"
    ;;
  add)
    name="${2:?}"; shift 2
    template=browser; color=red; disposable=false; internet=nym; mem=1536; vcpu=2
    iso=""; kind=""; boot=iso; disk_gb=16
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --template) template=$2; shift 2;;
        --iso) iso=$2; template=iso; shift 2;;
        --kind) kind=$2; shift 2;;
        --boot) boot=$2; shift 2;;
        --disk-gb) disk_gb=$2; shift 2;;
        --color) color=$2; shift 2;;
        --internet) internet=$2; shift 2;;
        --mem) mem=$2; shift 2;;
        --vcpu) vcpu=$2; shift 2;;
        --disposable) disposable=true; shift;;
        *) echo "unknown: $1" >&2; exit 1;;
      esac
    done
    [[ $internet == proxy ]] && internet=nym
    [[ $template == iso && -z $iso ]] && { echo "need --iso"; exit 1; }
    [[ $template == iso && $mem == 1536 ]] && mem=2048
    case "${kind:-}" in
      disposable) disposable=true; kind=disposable;;
      appvm|template) disposable=false;;
      "") kind=appvm; [[ $disposable == true ]] && kind=disposable;;
      *) echo "bad kind"; exit 1;;
    esac
    [[ $internet =~ ^(nym|i2p|tor|nym-tor|i2p-tor|tor-nym|i2p-nym|none)$ ]] || { echo "internet=nym|i2p|tor|nym-tor|i2p-tor|tor-nym|i2p-nym|none"; exit 1; }
    read -r IP MAC SOCKS < <(py <<'PY'
import json,os
z=json.load(open(os.environ["ZONE_JSON"]))
ui={int(c["ip"].split(".")[-1]) for c in z.values() if c.get("ip")}
us={c["socks"] for c in z.values() if c.get("socks")}
um={int(c["mac"].split(":")[-1],16) for c in z.values() if c.get("mac")}
print(f"10.0.0.{next(i for i in range(11,250) if i not in ui)} 02:b0:00:00:00:{next(i for i in range(0x11,0xfe) if i not in um):02x} {next(p for p in range(1081,1200) if p not in us)}")
PY
)
    NAME=$name TEMPLATE=$template COLOR=$color DISP=$disposable NET=$internet MEM=$mem VCPU=$vcpu \
    IP=$IP MAC=$MAC SOCKS=$SOCKS ISO=$iso KIND=$kind BOOT=$boot DISKGB=$disk_gb py <<'PY'
import json,os
p=os.environ["ZONE_JSON"]; z=json.load(open(p)); n=os.environ["NAME"]
assert n not in z and n.replace("-","").replace("_","").isalnum(), "bad/exists"
k=os.environ["KIND"]
e={"template":os.environ["TEMPLATE"],"ip":os.environ["IP"],"mac":os.environ["MAC"],
   "socks":int(os.environ["SOCKS"]),"mem":int(os.environ["MEM"]),"vcpu":int(os.environ["VCPU"]),
   "disposable":os.environ["DISP"]=="true" or k=="disposable","kind":k,"color":os.environ["COLOR"],
   "internet":os.environ["NET"],"usb":[],"apps":[],"panic":"keep","diskGb":16}
iso=os.environ.get("ISO") or ""
if os.environ["TEMPLATE"]=="iso" or iso:
 e.update(template="iso",iso=iso,boot=os.environ.get("BOOT") or "iso",
          diskGb=int(os.environ.get("DISKGB") or 16))
z[n]=e; json.dump(z,open(p,"w"),indent=2); print(json.dumps({n:e},indent=2))
print("start: bunker-zone-start", n if e.get("template")=="iso" else n)
print("" if e.get("template")=="iso" else "Next: sudo nixos-rebuild switch --flake .#host")
PY
  ;;
  set)
    NAME="${2:?}" ARGS="${*:3}" py <<'PY'
import json,os
p=os.environ["ZONE_JSON"]; z=json.load(open(p)); n=os.environ["NAME"]
assert n in z
for pair in os.environ["ARGS"].split():
 k,v=pair.split("=",1); vl=v.lower()
 if k in ("socks","mem","vcpu"): z[n][k]=int(v)
 elif k in ("diskGb","disk_gb"): z[n]["diskGb"]=int(v)
 elif k=="disposable":
  z[n][k]=vl in ("true","1","on"); z[n]["kind"]="disposable" if z[n][k] else "appvm"
 elif k=="kind":
  assert v in ("appvm","disposable","template"); z[n][k]=v; z[n]["disposable"]=v=="disposable"
 elif k in ("template","ip","mac","color","internet","iso","boot","disk","panic"):
  if k=="panic": assert v in ("keep","lock","wipe")
  if k=="internet": assert v in ("nym","i2p","tor","nym-tor","i2p-tor","tor-nym","i2p-nym","none")
  z[n][k]=v
  if k=="iso" and v: z[n]["template"]="iso"
 elif k in ("layer","invisible"):
  raise SystemExit("hide/invisible: use bunker TUI (u unlock, then i) — not public zones.json")
 else: raise SystemExit(f"bad key {k}")
json.dump(z,open(p,"w"),indent=2); print(json.dumps({n:z[n]},indent=2))
PY
  ;;
  rm|delete) NAME="${2:?}" py <<'PY'
import json,os
p=os.environ["ZONE_JSON"]; z=json.load(open(p)); n=os.environ["NAME"]
del z[n]; json.dump(z,open(p,"w"),indent=2); print("removed",n)
PY
  ;;
  rename|mv) OLD="${2:?}" NEW="${3:?}" py <<'PY'
import json,os,re
p=os.environ["ZONE_JSON"]; z=json.load(open(p)); o,n=os.environ["OLD"],os.environ["NEW"]
assert o in z and n not in z and re.fullmatch(r"[A-Za-z0-9_-]+",n)
z[n]=z.pop(o); json.dump(z,open(p,"w"),indent=2); print(f"renamed {o}→{n}")
print("Next: sudo nixos-rebuild switch --flake .#host")
PY
  ;;
  apps|usb)
    FIELD=$1 NAME="${2:?}" OP="${3:?}" PKG="${4:?}" py <<'PY'
import json,os,re
p=os.environ["ZONE_JSON"]; z=json.load(open(p))
n,op,pkg,f=os.environ["NAME"],os.environ["OP"],os.environ["PKG"],os.environ["FIELD"]
assert n in z
if f=="usb": assert re.match(r"^[0-9a-fA-F]+:[0-9a-fA-F]+$",pkg)
lst=list(z[n].get(f) or [])
if op=="add":
 if pkg not in lst: lst.append(pkg)
elif op=="rm": lst=[x for x in lst if x!=pkg]
else: raise SystemExit("add|rm")
z[n][f]=lst; json.dump(z,open(p,"w"),indent=2); print(json.dumps({n:z[n]},indent=2))
PY
  ;;
  -h|--help|"") sed -n '2,3p' "$0" | sed 's/^# //';;
  *) echo "unknown: $1" >&2; exit 1;;
esac
