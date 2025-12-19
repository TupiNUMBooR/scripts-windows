#!/usr/bin/env bash
set -euo pipefail
# Set ID3 tag for artist.

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 file1 [file2 ...]"
  echo "  also: id3v2 [-A album] [-a artist] [-t title] [-T track] file1 [file2 ...]"
  exit 0
fi

ARTIST="Space Dreamer"

id3v2 -a "$ARTIST" "$@"
