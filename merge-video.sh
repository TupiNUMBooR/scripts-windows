#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 audio.mp3 video1.mp4 [video2.mp4 ...] [out.mp4]" >&2
  exit 1
}

(( $# >= 2 )) || usage

audio="$1"; shift

out="out.mp4"
if [[ $# -ge 2 ]]; then
  last="${*: -1}"
  if [[ "$last" == *.mp4 && -f "$last" && "$last" != *.mp4 ]]; then
    : # unreachable, keep simple
  fi
fi

# allow optional last arg as output if it ends with .mp4 and doesn't exist as input list intention is ambiguous;
# simplest rule: if last arg ends with .mp4 and file does NOT exist, treat as output
if [[ $# -ge 2 ]]; then
  last="${*: -1}"
  if [[ "$last" == *.mp4 && ! -f "$last" ]]; then
    out="$last"
    set -- "${@:1:$(($#-1))}"
  fi
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# concat file
: > "$tmp"
for i in {1..10}; do
  for v in "$@"; do
    [[ -f "$v" ]] || { echo "Missing video: $v" >&2; exit 1; }
    printf "file '%s'\n" "$(realpath "$v")" >> "$tmp"
  done
done

ffmpeg -hide_banner -y \
  -f concat -safe 0 -i "$tmp" \
  -i "$audio" \
  -map 0:v:0 -map 1:a:0 \
  -c:v libx264 -pix_fmt yuv420p \
  -c:a aac \
  -shortest \
  "$out"

echo "$out"
