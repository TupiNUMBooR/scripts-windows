#!/usr/bin/env bash
set -euo pipefail

l=${1-16}
tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${l} | xargs
