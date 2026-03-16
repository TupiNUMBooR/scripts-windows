#!/usr/bin/env bash
set -euo pipefail

image="$1"
music="$2"
output="$3.mp3"

tmp_cover=$(mktemp --suffix=.jpg)

ffmpeg -hide_banner -y \
  -i "$image" \
  -vf "scale='min(1000,iw)':-1" \
  "$tmp_cover"

ffmpeg -hide_banner \
  -i "$music" \
  -i "$tmp_cover" \
  -map 0:a \
  -map 1:v \
  -c copy \
  -id3v2_version 3 \
  -metadata:s:v title="Album cover" \
  -metadata:s:v comment="Cover (front)" \
  "$output"

rm "$tmp_cover"
