#!/usr/bin/env bash
set -euo pipefail

sync_newer() {
  local a=$1
  local b=$2

  [[ -f $a || -f $b ]] || { echo "sync: neither $a nor $b exists"; return 0; }

  [[ -f $a && ! -f $b ]] && { cp -f "$a" "$b"; echo "sync: $a -> $b"; return; }
  [[ -f $b && ! -f $a ]] && { cp -f "$b" "$a"; echo "sync: $b -> $a"; return; }

  [[ $a -nt $b ]] && { cp -f "$a" "$b"; echo "sync: $a -> $b"; } || { cp -f "$b" "$a"; echo "sync: $b -> $a"; }
}

SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WSL_FILES_DIR="$SCRIPTS_DIR/wsl"

cp "$WSL_FILES_DIR/.bashrc" ~/.bashrc
cp "$WSL_FILES_DIR/.profile" ~/.bash_profile
mkdir -p ~/.{config,cache}/gallery-dl
cp "$WSL_FILES_DIR/gallery-dl.conf" ~/.config/gallery-dl/config.json

sync_newer "$WSL_FILES_DIR/cache.sqlite3" ~/.cache/gallery-dl/cache.sqlite3

pacman -Sy --needed --ask=4 archlinux-keyring
pacman -Su --ask=4
pacman -S --needed --ask=4 - < "$WSL_FILES_DIR/packages.pacman.txt"

pipx install gallery-dl
pipx upgrade gallery-dl
pipx ensurepath

if ! locale -a | grep -qx 'en_US.utf8'; then
  sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  locale-gen
  localectl set-locale LANG=en_US.UTF-8
fi

if [[ "$SHELL" != "/bin/bash" ]]; then
  chsh -s /bin/bash
  reboot
fi

echo "WSL archlinux updated"
