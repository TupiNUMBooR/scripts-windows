#!/usr/bin/env bash
set -euo pipefail
# Set ID3 tags for music files based on their filenames.
# Filenames should be in the format: "01 Song Title.mp3"

ARTIST="Space Dreamer"
ALBUM=""

help() {
  echo "Usage: $0 [-h] [-A album] [-a artist] file1 [file2 ...]"
  echo "  also: id3v2 [-A album] [-a artist] file1 [file2 ...]"
  exit 0
}

if [[ $# -eq 0 ]]; then
  help
fi

while getopts "A:a:h" opt; do
    case "$opt" in
        A) ALBUM="$OPTARG" ;;
        a) ARTIST="$OPTARG" ;;
        h) help ;;
    esac
done
shift $((OPTIND - 1))

for f in "$@"; do
    BASE="$(basename "$f")"
    NAME="${BASE%.*}"

    TRACK="${NAME%% *}"
    TITLE="${NAME#* }"

    echo id3v2 -a "$ARTIST" -A "$ALBUM" -T "$TRACK" -t "$TITLE" "$f"
         id3v2 -a "$ARTIST" -A "$ALBUM" -T "$TRACK" -t "$TITLE" "$f"
done
