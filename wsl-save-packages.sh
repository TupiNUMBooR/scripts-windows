#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(dirname "$0")"

pacman -Qqe > "$SCRIPTS_DIR/wsl/packages.txt"
