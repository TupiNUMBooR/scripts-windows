#!/usr/bin/env bash
set -euo pipefail
. .env

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <image> <music> <output_title>"
  exit 1
fi

# scripts_dir="$(cd "$(dirname "$0")" && pwd)"
image="$1"
music="$2"
bin="$(dirname "$0")"
image2x="${image%.*}-2x.jpeg"
output="$3.mp4"

if [[ ! -f "$image2x" ]]; then
  "$GIGAPIXEL" \
    --model cgi \
    --scale 2 \
    --input "$image" \
    --suffix "-2x" \
    -f jpeg \
    --output "$(dirname "$image")"
  echo "Created 2x image: $image2x"
else
  echo "Using existing 2x image: $image2x"
fi

ffmpeg -i "$image2x" -i "$music" \
  -hide_banner -y \
  -map 0:v -map 1:a \
  -c:v libx264 -preset slow -crf 15 \
  -c:a copy \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -movflags +faststart \
  -pix_fmt yuv420p \
  "$output"
echo "Created AMV: $output"
