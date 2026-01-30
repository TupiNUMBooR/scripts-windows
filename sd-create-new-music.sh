#!/usr/bin/env bash
set -euo pipefail
# shopt -s nullglob

# shellcheck disable=SC1091
. .env

dir="$(date +%m%d-%H%M)"

cd /mnt/d/k/art/manual-youtube
mv music/*.txt bonus/ || :
cp -n music/*.mp3 bonus/ || :
cp -n images/*.jpeg bonus/ || :
sd-autocut-2.sh images music "../$dir"
/mnt/c/Windows/explorer.exe "d:\\k\\art\\$dir"
