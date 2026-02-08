#!/usr/bin/env bash
set -euo pipefail
# shopt -s nullglob
. .env

usage() {
  echo "Usage: $0 [count:-1]"
  exit 1
}

if [[ $# -gt 1 ]]; then
  usage
fi

count=${1:-1}
dir="$(date +%m%d-%H%M)"

if [[ ! ${1:-1} =~ ^[0-9]+$ ]]; then
  usage
fi

: "${SD_TMP_DIR:?SD_TMP_DIR is not set}"

find "$SD_TMP_DIR" -type f -mtime +7 -delete

cd /mnt/d/k/art/manual-youtube

mv music/*.txt bonus/ || :
cp -n music/*.mp3 bonus/ || :
cp -n images/*.jpeg bonus/ || :

for i in $(seq 1 "$count"); do
  sd-autocut-2.sh images music "../$dir"
done

/mnt/c/Windows/explorer.exe "d:\\k\\art"

