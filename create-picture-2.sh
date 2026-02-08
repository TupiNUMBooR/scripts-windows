#!/usr/bin/env bash
set -euo pipefail

. .env

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

need curl
need jq
need date
need tr
need sed
need head
need grep

: "${CF_IMAGE_API_URL:?Set CF_IMAGE_API_URL (your workers.dev URL)}"
: "${CF_IMAGE_API_KEY:?Set CF_IMAGE_API_KEY (your Worker API_KEY)}"

# ---- defaults ----
num=1
size="1024x1536"

usage() {
  cat >&2 <<'EOF'
Usage:
  create-picture-2.sh [-n NUM] [-s WxH] [PROMPT...]
  echo "prompt" | create-picture-2.sh [-n NUM] [-s WxH]

Env:
  CF_IMAGE_API_URL   https://<worker>.<subdomain>.workers.dev
  CF_IMAGE_API_KEY   your-secret-api-key
EOF
  exit 1
}

while getopts ":n:s:h" opt; do
  case "$opt" in
    n) num="$OPTARG" ;;
    s) size="$OPTARG" ;;
    h) usage ;;
    :) die "Option -$OPTARG requires an argument" ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

[[ "$num" =~ ^[1-9][0-9]*$ ]] || die "Invalid -n: $num"
[[ "$size" =~ ^[0-9]{3,4}x[0-9]{3,4}$ ]] || die "Invalid -s: $size"

# ---- input ----
if [[ $# -gt 0 ]]; then
  prompt="$*"
else
  prompt="$(cat)"
fi

prompt="$(printf '%s' "$prompt" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[[ -n "$prompt" ]] || die "Empty prompt"

# Repo API accepts only {"prompt": "..."} (size is not documented), so we hint size in the prompt.
# prompt="$prompt. Portrait ${size}. No text, no letters, no logos, no watermark."

# ---- temp workspace ----
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ts="$(date +%m%d-%H%M%S)"
prefix="image-$ts"

for i in $(seq 1 "$num"); do
  out="${prefix}-${i}.jpg"
  resp_body="$tmp/resp-${i}.bin"
  resp_hdr="$tmp/resp-${i}.hdr"
  : >"$resp_body"
  : >"$resp_hdr"

  code="$(curl -sS \
    -D "$resp_hdr" \
    -o "$resp_body" \
    -w "%{http_code}" \
    -X POST "$CF_IMAGE_API_URL" \
    -H "Authorization: Bearer $CF_IMAGE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg p "$prompt" '{prompt:$p}')" \
    || true)"

  if [[ "$code" != "200" ]]; then
    echo "HTTP $code" >&2

    cf_ray="$(grep -i '^cf-ray:' "$resp_hdr" | head -n1 | sed 's/\r$//' || true)"
    [[ -n "$cf_ray" ]] && echo "$cf_ray" >&2

    req_id="$(grep -i '^x-request-id:' "$resp_hdr" | head -n1 | sed 's/\r$//' || true)"
    [[ -n "$req_id" ]] && echo "$req_id" >&2

    ct="$(grep -i '^content-type:' "$resp_hdr" | head -n1 | sed 's/\r$//' || true)"
    [[ -n "$ct" ]] && echo "$ct" >&2

    echo "--- response headers ---" >&2
    sed 's/\r$//' "$resp_hdr" >&2 || true

    echo "--- response body (first 4096 bytes) ---" >&2
    head -c 4096 "$resp_body" >&2 || true
    echo -e "\n--- end ---" >&2

    die "Image generation failed"
  fi

  mv -f "$resp_body" "$out"
  [[ -s "$out" ]] || die "Empty output file: $out"
  echo "Saved $out"
done
