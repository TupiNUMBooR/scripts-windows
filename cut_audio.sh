#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <input> <output.aac> <start> <duration>"
  exit 1
fi

input="$1"
output="$2"
start="$3"
duration="$4"

ffmpeg -ss "$start" -i "$input" -t "$duration" \
  -c:a aac -b:a 192k \
  "$output"
