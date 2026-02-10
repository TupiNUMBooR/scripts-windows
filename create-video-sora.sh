#!/usr/bin/env bash
set -euo pipefail

. .env

usage() {
  cat >&2 <<'EOF'
Usage:
  create-video-sora.sh [-n NUM] [-t SECONDS] [-s WxH] [PROMPT...]
  echo "prompt" | create-video-sora.sh [-n NUM] [-t SECONDS] [-s WxH]
Options:
  -n NUM     count (1..4, default: 1)
  -t SECONDS seconds (default: 4)
  -s WxH     size, e.g. 720x1280 (default: 720x1280)
Env:
  OPENAI_API_KEY (required)
EOF
  exit 2
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
die() { echo "ERROR: $*" >&2; exit 1; }

COUNT=1
SECONDS_LEN=4
SIZE="720x1280"

while getopts ":n:t:s:h" opt; do
  case "$opt" in
    n) COUNT="$OPTARG" ;;
    t) SECONDS_LEN="$OPTARG" ;;
    s) SIZE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

: "${OPENAI_API_KEY:?Set OPENAI_API_KEY}"

need curl
need jq

if [[ $# -gt 0 ]]; then PROMPT="$*"; else PROMPT="$(cat)"; fi
[[ -n "${PROMPT//[[:space:]]/}" ]] || die "Empty prompt"

# validate count (simple)
[[ "$COUNT" =~ ^[0-9]+$ ]] || die "-n must be an integer"
(( COUNT >= 1 && COUNT <= 4 )) || die "-n must be 1..4"

json_escape() { jq -Rs . <<<"$1"; }

create_payload=$(
  cat <<EOF
{
  "model": "sora-2",
  "prompt": $(json_escape "$PROMPT"),
  "seconds": "$SECONDS_LEN",
  "size": "$SIZE"
}
EOF
)

poll_and_download() {
  local i="$1"

  local resp video_id deadline status progress v out
  resp=$(curl -sS https://api.openai.com/v1/videos \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$create_payload")

  video_id=$(jq -r '.id // empty' <<<"$resp")
  [[ -n "$video_id" ]] || { echo "$resp" >&2; die "[$i] No video id in response"; }

  echo "[$i] video_id=$video_id" >&2

  deadline=$((SECONDS + 300))
  while :; do
    v=$(curl -sS "https://api.openai.com/v1/videos/$video_id" \
      -H "Authorization: Bearer $OPENAI_API_KEY")

    status=$(jq -r '.status // "unknown"' <<<"$v")
    progress=$(jq -r '.progress // empty' <<<"$v")
    [[ -n "$progress" ]] && echo "[$i] status=$status progress=${progress}%" >&2 || echo "[$i] status=$status" >&2

    case "$status" in
      completed) break ;;
      failed)
        err=$(jq -r '.error.message? // .error? // "unknown error"' <<<"$v")
        die "[$i] Video failed: $err"
        ;;
    esac

    (( SECONDS < deadline )) || die "[$i] Timeout waiting for video ($video_id)"
    sleep 5
  done

  out="${video_id}.sora.mp4"
  curl -sS -L \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    "https://api.openai.com/v1/videos/$video_id/content" \
    -o "$out"

  echo "[$i] saved: $out" >&2
  echo "$out"
}

echo "Creating $COUNT video(s) with prompt: $PROMPT" >&2

# run in parallel
for i in $(seq 1 "$COUNT"); do
  poll_and_download "$i" &
done

wait
echo "All done!" >&2
