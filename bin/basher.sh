#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE='ghcr.io/tupinumboor/basher:latest'
ENV_FILE="$SCRIPT_DIR/../.env"

printf 'Pulling Basher image: %s\n' "$IMAGE"
if ! docker pull "$IMAGE"; then
  printf 'Warning: could not pull the image; using the local image if available.\n' >&2
fi

exec docker run --rm -it \
  --volume "$PWD:/workspace" \
  --env-file "$ENV_FILE" \
  "$IMAGE"
