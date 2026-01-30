#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 && $# -ne 0 ]]; then
  echo "Usage: $0 <image> <audio> <output>"
  exit 1
fi

image="${1:-upscale.jpeg}"
audio="${2:-playlist.m4a}"
output="${3:-playlist.mp4}"

ffmpeg -i "$image" -i "$audio" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset slow -crf 15 \
  -c:a copy \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -movflags +faststart \
  -pix_fmt yuv420p \
  "$output"
