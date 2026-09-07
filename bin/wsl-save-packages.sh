#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

pacman -Qqe > "$SCRIPTS_DIR/wsl/packages.pacman.txt"
