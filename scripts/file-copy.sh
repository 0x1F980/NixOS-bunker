#!/usr/bin/env bash
# Mediated file copy (Qubes-like). Host stages then shreds — no guest FS mount.
# Usage:
#   bunker-file copy <srcZone>:<path> <dstZone>:<path>
#   bunker-file put  <zone> <hostPath> [remotePath]
#   bunker-file get  <zone> <remotePath> [hostPath]
set -euo pipefail
# shellcheck source=lib-common.sh
source "$(dirname "$0")/lib-common.sh"

STAGING="${BUNKER_FILE_DIR:-/var/lib/bunker/file-xfer}"
mkdir -p "$STAGING"
chmod 700 "$STAGING"

wipe() {
  local f
  for f in "$@"; do
    [[ -e $f ]] || continue
    if [[ -d $f ]]; then
      find "$f" -type f -exec shred -u -n 1 {} \; 2>/dev/null || true
      rm -rf "$f"
    else
      shred -u -n 1 "$f" 2>/dev/null || rm -f "$f"
    fi
  done
}

scp_to() {
  # scp_to ip local remote
  local ip=$1 localp=$2 rem=$3
  local pass=${BUNKER_ZONE_PASS:-zone}
  local opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12)
  local rflag=()
  [[ -d $localp ]] && rflag=(-r)
  if [[ -n ${BUNKER_ZONE_SSH_KEY:-} && -f $BUNKER_ZONE_SSH_KEY ]]; then
    scp "${rflag[@]}" -i "$BUNKER_ZONE_SSH_KEY" "${opts[@]}" "$localp" "zone@${ip}:${rem}"
  elif command -v sshpass >/dev/null; then
    sshpass -p "$pass" scp "${rflag[@]}" "${opts[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      "$localp" "zone@${ip}:${rem}"
  else
    scp "${rflag[@]}" "${opts[@]}" "$localp" "zone@${ip}:${rem}"
  fi
}

scp_from() {
  local ip=$1 rem=$2 localp=$3
  local pass=${BUNKER_ZONE_PASS:-zone}
  local opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12)
  # remote may be file or dir — use -r always safe for files too on openssh
  if [[ -n ${BUNKER_ZONE_SSH_KEY:-} && -f $BUNKER_ZONE_SSH_KEY ]]; then
    scp -r -i "$BUNKER_ZONE_SSH_KEY" "${opts[@]}" "zone@${ip}:${rem}" "$localp"
  elif command -v sshpass >/dev/null; then
    sshpass -p "$pass" scp -r "${opts[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      "zone@${ip}:${rem}" "$localp"
  else
    scp -r "${opts[@]}" "zone@${ip}:${rem}" "$localp"
  fi
}

parse_spec() {
  # sets _zone _path from zone:path
  local spec=$1
  [[ $spec == *:* ]] || {
    echo "need zone:path (got: $spec)" >&2
    return 1
  }
  _zone=${spec%%:*}
  _path=${spec#*:}
  [[ -n $_zone && -n $_path ]] || {
    echo "bad spec: $spec" >&2
    return 1
  }
}

cmd_copy() {
  local sspec=$1 dspec=$2
  local _zone _path szone spath dzone dpath sip dip stage
  parse_spec "$sspec"
  szone=$_zone
  spath=$_path
  parse_spec "$dspec"
  dzone=$_zone
  dpath=$_path
  sip=$(bunker_zone_ip "$szone")
  dip=$(bunker_zone_ip "$dzone")
  [[ -n $sip && -n $dip ]] || {
    echo "need IPs for $szone / $dzone" >&2
    exit 1
  }
  stage=$(mktemp -d "$STAGING/copy.XXXXXX")
  trap 'wipe "$stage"' EXIT
  echo "==> $szone:$spath → staging"
  scp_from "$sip" "$spath" "$stage/payload"
  # if scp put a directory named payload, or a file
  local payload=$stage/payload
  [[ -e $payload ]] || payload=$(find "$stage" -mindepth 1 -maxdepth 1 | head -1)
  [[ -e ${payload:-} ]] || {
    echo "empty transfer" >&2
    exit 1
  }
  # ensure remote parent exists
  bunker_ssh_zone "$dip" "mkdir -p \"\$(dirname \"$dpath\")\""
  echo "==> staging → $dzone:$dpath"
  scp_to "$dip" "$payload" "$dpath"
  wipe "$stage"
  trap - EXIT
  echo "OK copy $szone:$spath → $dzone:$dpath"
}

cmd_put() {
  local zone=$1 hostp=$2 rem=${3:-}
  local ip
  ip=$(bunker_zone_ip "$zone")
  [[ -n $ip ]] || {
    echo "no IP for $zone" >&2
    exit 1
  }
  [[ -e $hostp ]] || {
    echo "missing $hostp" >&2
    exit 1
  }
  [[ -n $rem ]] || rem="/home/zone/$(basename "$hostp")"
  bunker_ssh_zone "$ip" "mkdir -p \"\$(dirname \"$rem\")\""
  scp_to "$ip" "$hostp" "$rem"
  echo "OK put → $zone:$rem"
}

cmd_get() {
  local zone=$1 rem=$2 hostp=${3:-}
  local ip stage
  ip=$(bunker_zone_ip "$zone")
  [[ -n $ip ]] || {
    echo "no IP for $zone" >&2
    exit 1
  }
  [[ -n $hostp ]] || hostp="./$(basename "$rem")"
  stage=$(mktemp -d "$STAGING/get.XXXXXX")
  trap 'wipe "$stage"' EXIT
  scp_from "$ip" "$rem" "$stage/payload"
  local payload=$stage/payload
  [[ -e $payload ]] || payload=$(find "$stage" -mindepth 1 -maxdepth 1 | head -1)
  if [[ -d $payload ]]; then
    mkdir -p "$hostp"
    cp -a "$payload"/. "$hostp"/
  else
    mkdir -p "$(dirname "$hostp")"
    cp -a "$payload" "$hostp"
  fi
  wipe "$stage"
  trap - EXIT
  echo "OK get $zone:$rem → $hostp"
}

case "${1:-}" in
  copy)
    shift
    cmd_copy "${1:?srcZone:path}" "${2:?dstZone:path}"
    ;;
  put)
    shift
    cmd_put "${1:?zone}" "${2:?hostPath}" "${3:-}"
    ;;
  get)
    shift
    cmd_get "${1:?zone}" "${2:?remotePath}" "${3:-}"
    ;;
  *)
    echo "Usage: bunker-file copy <a>:<path> <b>:<path>"
    echo "       bunker-file put <zone> <hostPath> [remotePath]"
    echo "       bunker-file get <zone> <remotePath> [hostPath]"
    exit 1
    ;;
esac
