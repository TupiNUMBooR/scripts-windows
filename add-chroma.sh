#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <image>"
  exit 1
fi

input="$1"
output="${1%.*}-chroma.jpg"

# Get resolution (width x height)
dims=$(identify -format "%w %h" "$input")
read w h <<< "$dims"

convert "$input" -write MPR:orig +delete \
  \( MPR:orig -separate -delete 1,2 -affine 1.00,0,0,1.00,0,0 -transform -gravity Center -extent "${w}x$h" \) \
  \( MPR:orig -separate -delete 0,2 -affine 1.006,0,0,1.001,0,0 -transform -gravity Center -extent "${w}x$h" \) \
  \( MPR:orig -separate -delete 0,1 -affine 1.004,0,0,1.003,0,0 -transform -gravity Center -extent "${w}x$h" \) \
  -combine "$output"

