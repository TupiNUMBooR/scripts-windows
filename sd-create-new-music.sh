#!/usr/bin/env bash
set -euo pipefail
# shopt -s nullglob
. .env

dir="$(date +%m%d-%H%M)"

: "${SD_TMP_DIR:?SD_TMP_DIR is not set}"
find "$SD_TMP_DIR" -type f -mtime +7 -delete

cd /mnt/d/k/art/manual-youtube

mv music/*.txt bonus/ || :
cp -n music/*.mp3 bonus/ || :
cp -n images/*.jpeg bonus/ || :

sd-autocut-2.sh images music "../$dir"

/mnt/c/Windows/explorer.exe "d:\\k\\art\\$dir"

