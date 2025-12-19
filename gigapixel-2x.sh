#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <image>"
  exit 1
fi

image="$1"
gigapixel="/mnt/c/Program Files/Topaz Labs LLC/Topaz Gigapixel AI/gigapixel.exe"

if [[ "$1" == "-h" ]]; then
  "$gigapixel" --help
  exit 1
fi


"$gigapixel" \
  --verbose \
  --model cgi \
  --scale 2 \
  --input "$image" \
  --suffix "-gigapixel-cgi-2x" \
  -f jpeg \
  --output "$(dirname "$image")"
