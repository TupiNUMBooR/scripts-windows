#!/usr/bin/env bash
set -euo pipefail

git archive -o "$(basename "$PWD").zip" HEAD
