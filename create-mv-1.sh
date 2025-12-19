#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <image> <music> <output>"
  exit 1
fi

# scripts_dir="$(cd "$(dirname "$0")" && pwd)"
image="$1"
music="$2"
bin="$(dirname "$0")"
upscaled_image="${image%.*}-gigapixel-cgi-2x.jpeg"
output="$3"

"$bin/gigapixel-2x.sh" "$image" 

"$bin/combine_picture_and_audio.sh" "$upscaled_image" "$music" "$output.mp4"
