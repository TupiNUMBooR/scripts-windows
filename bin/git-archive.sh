#!/usr/bin/env bash
set -euo pipefail
# git-archive.sh

name="$(basename "$PWD")"
timestamp="$(date -u +"%Y%m%d_%H%M%SZ")"
archive="${name}-${timestamp}.zip"

git archive HEAD -o "$archive"

size="$(du -h "$archive" | cut -f1)"

echo "Archived to $archive ($size)"
