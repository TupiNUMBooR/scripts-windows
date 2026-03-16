#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <image> <music> <output_title>"
  exit 1
fi

image="$1"
music="$2"
output="$3.mp4"

if [[ -f "$output" ]]; then
  read -rp "File $output exists. Overwrite? [y/N] " ans
  [[ $ans == [Yy]* ]] || exit 1
fi

ffmpeg -hide_banner -y \
  -loop 1 -framerate 1 -i "$image" -i "$music" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset slow -crf 18 \
  -c:a copy \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -pix_fmt yuv420p \
  -shortest \
  -movflags +faststart \
  "$output"

echo "Created AMV: $output"
