#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(dirname "$0")"

pacman -Rns $(comm -23 <(pacman -Qqe | sort) <(sort "$SCRIPTS_DIR/wsl/packages.txt"))
paccache -ruk0
paccache -rk1
