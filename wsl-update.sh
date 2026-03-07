#!/usr/bin/env bash
set -euo pipefail

sync_newer() {
  local a=$1
  local b=$2

  # nothing to do if both files are missing
  [[ -f $a || -f $b ]] || return 0

  # copy if only one file exists
  [[ -f $a && ! -f $b ]] && { cp -f "$a" "$b"; return; }
  [[ -f $b && ! -f $a ]] && { cp -f "$b" "$a"; return; }

  # both exist: copy the newer one
  [[ $a -nt $b ]] && cp -f "$a" "$b" || cp -f "$b" "$a"
}

. .env

SCRIPTS_DIR="$(dirname "$0")"
WSL_FILES_DIR="$SCRIPTS_DIR/wsl"

cp "$WSL_FILES_DIR/.bashrc" ~/.bashrc
cp "$WSL_FILES_DIR/.profile" ~/.bash_profile
mkdir -p ~/.{config,cache}/gallery-dl
cp "$WSL_FILES_DIR/gallery-dl.conf" ~/.config/gallery-dl/config.json

sync_newer "$WSL_FILES_DIR/cache.sqlite3" ~/.cache/gallery-dl/cache.sqlite3

u=${USER?}
if [[ ! -e ~/.gitconfig && -f "/mnt/c/Users/$u/.gitconfig" ]]; then
  ln -s "/mnt/c/Users/$u/.gitconfig" ~/.gitconfig
fi

git config --global init.defaultBranch dev
git config --global push.autoSetupRemote true
git config --global core.autocrlf input

pacman -Sy --needed --ask=4 archlinux-keyring
pacman -Su --ask=4
pacman -S --needed --ask=4 - < packages.txt

pipx install gallery-dl
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
