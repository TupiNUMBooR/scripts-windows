#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(dirname "$0")"

comm -23 <(pacman -Qqe | sort) <(sort "$SCRIPTS_DIR/wsl/packages.txt") | xargs -r pacman -Rns
pacman -Qtdq | xargs -r pacman -Rns
paccache -ruk0
paccache -rk1
