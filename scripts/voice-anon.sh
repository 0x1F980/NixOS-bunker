#!/usr/bin/env bash
# Simple voice anonymizer — pitch shift via sox (toggle on/off docs).
# Usage: bunker-voice-anon [on|off|once]
set -euo pipefail

MODE="${1:-once}"

case "$MODE" in
  on)
    echo "Enable a PipeWire loopback with sox pitch shift manually, or run:"
    echo "  $0 once   # process mic wav demo"
    echo "Full persistent PW filter graph is operator-configured per machine."
    ;;
  off)
    echo "Disable any custom PipeWire voice-anon modules you enabled (pw-cli / helvum)."
    ;;
  once)
    IN="${2:-/tmp/bunker-mic.wav}"
    OUT="${3:-/tmp/bunker-mic-anon.wav}"
    if [[ ! -f "$IN" ]]; then
      echo "Record input to $IN first, or pass path: $0 once in.wav out.wav"
      exit 1
    fi
    sox "$IN" "$OUT" pitch 300
    echo "Wrote anonymized audio to $OUT"
    ;;
  *)
    echo "Usage: $0 [on|off|once]"
    exit 1
    ;;
esac
