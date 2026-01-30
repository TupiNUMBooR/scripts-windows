#!/usr/bin/env bash
set -euo pipefail
. .env

while getopts "h" o; do
  case $o in
  h)
    "$GIGAPIXEL" --help
    exit 0
  ;;
  esac
done
shift $(($OPTIND - 1))

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [-h] dir_from"
  exit 1
fi

dir="$1"
dir2x="${dir}-2x"
missing_files=()

for f in "$dir"/*; do
  bn="$(basename "$f")"
  fn="$dir2x/${bn%.*}-2x.jpeg"
  if [[ ! -f "$fn" ]]; then
    missing_files+=("$f")
  fi
done

if (( ${#missing_files[@]} == 0 )); then
  echo "All files already in $dir2x"
  exit 1
fi

echo "Processing ${#missing_files[@]} files with Gigapixel AI..."

time "$GIGAPIXEL" \
  --model cgi \
  --scale 2 \
  --input "${missing_files[@]}" \
  --suffix "-2x" \
  -f jpeg \
  --output "$dir2x"
