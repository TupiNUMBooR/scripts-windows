#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

comm -23 <(pacman -Qqe | sort) <(sort "$SCRIPTS_DIR/wsl/packages.pacman.txt") | xargs -r pacman -Rns
pacman -Qtdq | xargs -r pacman -Rns
paccache -ruk0
paccache -rk1
