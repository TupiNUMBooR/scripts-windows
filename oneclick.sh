#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <directory> <short_time_in_seconds>"
  exit 1
fi

directory="$1"
short_time="$2"
scripts_dir="$(cd "$(dirname "$0")" && pwd)"
audio_full="audio-full.aac"
video_full="video-full.mp4"
audio_short="audio-short.aac"
video_short="video-short.mp4"

cd "$directory"

if [[ ! -f "$audio_full" ]]; then
echo "Создание полного аудио файла..."
  "$scripts_dir/assemble_playlist.sh" playlist.xspf "$audio_full"
fi

if [[ ! -f "$video_full" ]]; then
  echo "Создание полного видео файла..."
  "$scripts_dir/combine_picture_and_audio.sh" cover-16x9.jpg "$audio_full" "$video_full"
fi

if [[ ! -f "$audio_short" ]]; then
  echo "Создание короткого аудио файла..."
  "$scripts_dir/cut_audio.sh" "$audio_full" "$audio_short" "$short_time" 10
fi

if [[ ! -f "$video_short" ]]; then
  echo "Создание короткого видео файла..."
  "$scripts_dir/combine_picture_and_audio.sh" cover-9x16.jpg "$audio_short" "$video_short"
fi
