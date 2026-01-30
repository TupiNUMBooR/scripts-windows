#!/usr/bin/env bash
set -euo pipefail
# shopt -s nullglob

# shellcheck disable=SC1091
. .env

dir="$(date +%m%d%H)"

cd /mnt/d/k/art/manual-youtube
mv suno/*.txt sunotxt/ || :
cp -n suno/*.mp3 sunotxt/ || :
sd-autocut-2.sh midjourney-2x suno "$dir"
/mnt/c/Windows/explorer.exe "d:\\k\\art\\manual-youtube\\$dir"
