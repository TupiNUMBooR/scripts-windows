#!/usr/bin/env bash
set -euo pipefail

. .env

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

need curl
need jq
need base64
need date

: "${OPENAI_API_KEY:?Set OPENAI_API_KEY in environment}"

# ---- defaults ----
num=1
size="1024x1024"

usage() {
  cat >&2 <<EOF
Usage:
  create-picture.sh [-n NUM] [-s SIZE] [PROMPT...]
  echo "prompt" | create-picture.sh [-n NUM] [-s SIZE]

Options:
  -n NUM     Number of images (default: 1)
  -s SIZE    Image size, e.g. 1024x1024, 1080x1920 (default: 1024x1024)
EOF
  exit 1
}

# ---- getopts ----
while getopts ":n:s:h" opt; do
  case "$opt" in
    n)
      num="$OPTARG"
      ;;
    s)
      size="$OPTARG"
      ;;
    h)
      usage
      ;;
    :)
      die "Option -$OPTARG requires an argument"
      ;;
    \?)
      die "Unknown option: -$OPTARG"
      ;;
  esac
done
shift $((OPTIND - 1))

# ---- validation ----
[[ "$num" =~ ^[1-9][0-9]*$ ]] || die "Invalid number of images: $num"
[[ "$size" =~ ^[0-9]{3,4}x[0-9]{3,4}$ ]] || die "Invalid size format: $size"

# ---- input ----
if [[ $# -gt 0 ]]; then
  prompt="$*"
else
  prompt="$(cat)"
fi

prompt="$(echo "$prompt" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[[ -n "$prompt" ]] || die "Empty prompt"
echo "Generating $num image(s) of size $size | Prompt: $prompt"

# ---- output prefix ----
ts="$(date +%m%d-%H%M%S)"
prefix="image-$ts"

# ---- API call ----
response="$(curl -sS https://api.openai.com/v1/images/generations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"gpt-image-1\",
    \"prompt\": $(jq -Rs . <<< \"$prompt\"),
    \"n\": $num,
    \"size\": \"$size\"
  }")"

count="$(jq '.data | length' <<< "$response")"
(( count > 0 )) || {
  echo "$response" | jq . >&2
  die "No images returned"
}

# ---- decode ----
for i in $(seq 0 $((count - 1))); do
  out="${prefix}-$((i + 1)).png"
  jq -r ".data[$i].b64_json" <<< "$response" \
    | base64 --decode > "$out"
  [[ -s "$out" ]] || die "Failed to write $out"
  echo "Saved $out"
done
