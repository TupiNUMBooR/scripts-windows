#!/usr/bin/env bash
set -euo pipefail
# shopt -s nullglob

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <repo-name.git>"
  exit 1
fi

git init
git remote add origin git@github.com:TupiNUMBooR/$1
git branch -M dev
git push -u origin dev

