#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <video> <audio> <output>"
  exit 1
fi

video="$1"
audio="$2"
output="$3"

# Получаем длину аудио в секундах
audio_duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$audio")

# ffmpeg: loop видео, пока не закончится аудио
ffmpeg \
  -stream_loop -1 -i "$video" \
  -i "$audio" \
  -t "$audio_duration" \
  -map 0:v -map 1:a \
  -c:v copy \
  -c:a copy \
  -movflags +faststart \
  -pix_fmt yuv420p \
  "$output"
