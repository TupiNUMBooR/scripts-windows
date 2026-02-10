#!/usr/bin/env bash
set -euo pipefail

for f in "$@"; do
  IN="$f"
  OUT="${IN%.*}.pingpong.mp4"

  TMP_REV="$(mktemp --suffix=.mp4)"
  TMP_LIST="$(mktemp --suffix=.txt)"

  # 1) Реверс видео и аудио
  ffmpeg -y -hide_banner -loglevel error \
    -i "$IN" \
    -vf reverse \
    -af areverse \
    "$TMP_REV"

  # 2) Список для concat
  cat > "$TMP_LIST" <<EOF
file '$(realpath "$IN")'
file '$TMP_REV'
EOF

  # 3) Склейка без перекодирования
  ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$TMP_LIST" -c copy "$OUT"

  # cleanup
  rm -f "$TMP_REV" "$TMP_LIST"

  echo "Done -> $OUT"
done
