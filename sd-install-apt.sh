#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt upgrade -y
sudo apt install -y id3v2 xmlstarlet ffmpeg imagemagick
