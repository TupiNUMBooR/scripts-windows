#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  download-mp3-from-youtube.sh <youtube-url-or-id> [more URLs or IDs...]

Examples:
  download-mp3-from-youtube.sh https://www.youtube.com/watch?v=dQw4w9WgXcQ
  download-mp3-from-youtube.sh beEIUG_yMVQ
  download-mp3-from-youtube.sh beEIUG_yMVQ dQw4w9WgXcQ
EOF
  exit 1
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' is required" >&2
    exit 1
  }
}

normalize_input() {
  local input="$1"

  if [[ "$input" =~ ^https?:// ]]; then
    printf '%s\n' "$input"
    return
  fi

  if [[ "$input" =~ ^[A-Za-z0-9_-]{11}$ ]]; then
    printf 'https://www.youtube.com/watch?v=%s\n' "$input"
    return
  fi

  echo "ERROR: unsupported input: $input" >&2
  exit 1
}

find_first_existing() {
  local path
  for path in "$@"; do
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

main() {
  [[ $# -gt 0 ]] || usage

  require_bin yt-dlp
  require_bin ffmpeg

  shopt -s nullglob

  local -a urls=()
  local input

  for input in "$@"; do
    urls+=("$(normalize_input "$input")")
  done

  echo "Will process:"
  printf '  %s\n' "${urls[@]}"

  read -r -p "Press Enter to continue or Ctrl+C to abort: " answer
  [[ -z "$answer" ]] || {
    echo "Aborted."
    exit 1
  }

  local url
  local id
  local audio
  local cover
  local base
  local out

  for url in "${urls[@]}"; do
    id="$(yt-dlp --get-id "$url" | head -n 1)"

    echo "Downloading: $url"
    echo "  id: $id"

    yt-dlp \
      -f "ba" \
      --write-thumbnail \
      -o "%(title)s [%(id)s].%(ext)s" \
      "$url"

    audio="$(find_first_existing \
      *"[${id}].m4a" \
      *"[${id}].webm" \
      *"[${id}].mp4" \
      *"[${id}].aac"
    )" || {
      echo "ERROR: audio file not found for id: $id" >&2
      continue
    }

    cover="$(find_first_existing \
      *"[${id}].webp" \
      *"[${id}].jpg" \
      *"[${id}].jpeg" \
      *"[${id}].png"
    )" || {
      echo "ERROR: thumbnail not found for id: $id" >&2
      continue
    }

    base="${audio%.*}"
    out="${base}.mp3"

    echo "Creating: $out"
    echo "  audio: $audio"
    echo "  cover: $cover"

    ffmpeg -y \
      -hide_banner \
      -i "$audio" \
      -i "$cover" \
      -map 0:a \
      -map 1:v \
      -c:a libmp3lame \
      -q:a 2 \
      -c:v mjpeg \
      -id3v2_version 3 \
      -metadata:s:v title="Album cover" \
      -metadata:s:v comment="Cover (front)" \
      "$out"

    echo "Cleaning up:"
    echo "  removing $audio"
    echo "  removing $cover"

    rm -f -- "$audio" "$cover"
  done

  echo "Done."
}

main "$@"
