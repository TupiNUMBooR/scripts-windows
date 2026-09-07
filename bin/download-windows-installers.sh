#!/usr/bin/env bash
set -Eeuo pipefail

# Download current Windows installers from vendor or project release sources.
# Run from WSL, Git Bash, or another Bash environment with curl installed.

OUTPUT_DIR=${1:-./dist}

mkdir -p "$OUTPUT_DIR"

download() {
  local url=$1
  local headers effective_url filename output

  headers=$(mktemp)
  trap 'rm -f "$headers"' RETURN
  effective_url=$(curl --fail --silent --show-error --head --location --retry 3 \
    --retry-delay 2 --dump-header "$headers" --output /dev/null \
    --write-out '%{url_effective}' "$url")

  filename=$(sed -n 's/^[Cc]ontent-[Dd]isposition:.*filename\*=[^'"'"']*''\([^;[:space:]]*\).*/\1/p; s/^[Cc]ontent-[Dd]isposition:.*filename="\([^"]*\)".*/\1/p; s/^[Cc]ontent-[Dd]isposition:.*filename=\([^;[:space:]]*\).*/\1/p' "$headers" | tail -n 1)
  if [[ -z $filename ]]; then
    filename=${effective_url%%\?*}
    filename=${filename##*/}
  fi
  if [[ -z $filename || $filename == windows || $filename == stable || $filename == latest ]]; then
    printf 'Could not determine the original filename for %s\n' "$url" >&2
    return 1
  fi

  output="$OUTPUT_DIR/$filename"
  if [[ -e $output ]]; then
    printf 'Skipping existing %s\n' "$filename"
    return 0
  fi

  printf 'Downloading %s...\n' "$filename"
  curl --fail --location --retry 3 --retry-delay 2 --output "$output" "$url"
}

github_latest_asset() {
  local repository=$1
  local pattern=$2

  curl --fail --location --silent --show-error \
    "https://api.github.com/repos/$repository/releases/latest" |
    sed -n 's/.*"browser_download_url": "\([^"]*\)".*/\1/p' |
    grep -E "$pattern" |
    head -n 1
}

# Full set. Keep FurMark here because it is useful for post-install hardware checks.
download 'https://www.7-zip.org/a/7z2601-x64.exe'
download 'https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi'
download 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US'
download 'https://net.geo.opera.com/opera/stable/windows'
download 'https://update.code.visualstudio.com/latest/win32-x64-user/stable'

QBITTORRENT_URL=$(github_latest_asset 'qbittorrent/qBittorrent' 'Windows.*x64.*\.exe|x64.*setup.*\.exe')
if [[ -z $QBITTORRENT_URL ]]; then
  printf 'Could not find the latest qBittorrent Windows asset.\n' >&2
  exit 1
fi
download "$QBITTORRENT_URL"

AMNEZIA_URL=$(github_latest_asset 'amnezia-vpn/amnezia-client' 'windows.*x64.*\.exe|x64.*\.exe')
if [[ -z $AMNEZIA_URL ]]; then
  printf 'Could not find the latest AmneziaVPN Windows asset.\n' >&2
  exit 1
fi
download "$AMNEZIA_URL"

download 'https://swupdate.openvpn.net/downloads/connect/openvpn-connect-3.7.2.4892_signed.msi'
download 'https://geeks3d.com/dl/get/?file=FurMark_1.38.0.0_2025-09-15.exe'

printf '\nDownloaded installers to: %s\n' "$OUTPUT_DIR"
