#!/usr/bin/env bash
set -euo pipefail

ARTIST="Space Dreamer"
ALBUM=""

while getopts "A:a:" opt; do
    case "$opt" in
        A) ALBUM="$OPTARG" ;;
        a) ARTIST="$OPTARG" ;;
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
