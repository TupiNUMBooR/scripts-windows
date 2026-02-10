#!/usr/bin/env bash
set -euo pipefail

cd /mnt/d/k/dev/yt-up
source .venv/bin/activate
./upload.py "$@"
