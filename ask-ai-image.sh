#!/usr/bin/env bash
set -euo pipefail

: "${OPENAI_API_KEY:?}"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

need curl
need jq
need base64

SCRIPT_NAME="$(basename "$0")"
ENDPOINT_HOST="api.openai.com"
ENDPOINT_PATH="/v1/images/generations"
ENDPOINT_URL="https://${ENDPOINT_HOST}${ENDPOINT_PATH}"

OPENAI_IMAGE_MODEL="${OPENAI_IMAGE_MODEL:-gpt-image-2}"
OPENAI_IMAGE_SIZE="${OPENAI_IMAGE_SIZE:-1024x1536}"
OPENAI_IMAGE_QUALITY="${OPENAI_IMAGE_QUALITY:-low}"
OPENAI_IMAGE_FORMAT="${OPENAI_IMAGE_FORMAT:-png}"
OUT_DIR="${OUT_DIR:-.}"
MAX_CHARS="${MAX_CHARS:-4000}"

log() {
  printf '[%s] [%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$SCRIPT_NAME" "$*" >&2
}

usage() {
  cat >&2 <<EOF
Usage:
  $SCRIPT_NAME [prompt...]
  $SCRIPT_NAME < prompt.txt

Env:
  OPENAI_API_KEY        required
  OPENAI_IMAGE_MODEL    default: gpt-image-2
  OPENAI_IMAGE_SIZE     default: 1024x1536
  OPENAI_IMAGE_QUALITY  default: low
  OPENAI_IMAGE_FORMAT   default: png
  OUT_DIR               default: .
  MAX_CHARS             default: 4000

Docs:
  Pricing:
    https://developers.openai.com/api/docs/pricing#image-generation

  Guide:
    https://developers.openai.com/api/docs/guides/image-generation
EOF
  exit 1
}

while getopts ":h" opt; do
  case "$opt" in
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

PROMPT="${*:-$(cat)}"

[[ -n "${PROMPT//[[:space:]]/}" ]] || die "Empty prompt"
((${#PROMPT} <= MAX_CHARS)) || die "Prompt too long (${#PROMPT} > $MAX_CHARS)"

# https://developers.openai.com/api/docs/pricing#image-generation
# https://developers.openai.com/api/docs/guides/image-generation#cost-and-latency
read -r image_input_price image_cached_price image_output_price text_input_price text_cached_price text_output_price < <(
  case "$OPENAI_IMAGE_MODEL" in
    gpt-image-2)      echo "8.00 2.00 30.00 5.00 1.25  0"    ;;
    gpt-image-1.5)    echo "8.00 2.00 32.00 5.00 1.25 10.00" ;;
    gpt-image-1-mini) echo "2.50 0.25  8.00 2.00 0.20  0"    ;;
    *)                echo "0 0 0 0 0 0" ;;
  esac
)

safe_name="$(
  printf '%s' "$PROMPT" \
  | tr '\n\r\t' ' ' \
  | cut -c 1-80 \
  | sed 's/[^[:alnum:]]/-/g; s/-\+/-/g; s/^-//; s/-$//'
)"

stamp="$(date -u +"%Y%m%d_%H%M%S")"

mkdir -p "$OUT_DIR"

base="$OUT_DIR/${stamp}-${safe_name:-image}"

json_file="${base}.json"
image_file="${base}.${OPENAI_IMAGE_FORMAT}"

payload="$(
  jq -n \
    --arg model "$OPENAI_IMAGE_MODEL" \
    --arg prompt "$PROMPT" \
    --arg size "$OPENAI_IMAGE_SIZE" \
    --arg quality "$OPENAI_IMAGE_QUALITY" \
    --arg format "$OPENAI_IMAGE_FORMAT" \
    '{
      model: $model,
      prompt: $prompt,
      size: $size,
      quality: $quality,
      output_format: $format
    }'
)"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

log "request model=$OPENAI_IMAGE_MODEL size=$OPENAI_IMAGE_SIZE quality=$OPENAI_IMAGE_QUALITY chars=${#PROMPT}"
log "json=$json_file"
log "image=$image_file"

log "POST ${ENDPOINT_HOST}${ENDPOINT_PATH} ->"

http_code="$(
  curl -sS -o "$tmp" -w '%{http_code}' \
    "$ENDPOINT_URL" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload"
)"

log "POST ${ENDPOINT_HOST}${ENDPOINT_PATH} <- $http_code"

jq 'del(.data[]?.b64_json)' "$tmp" > "$json_file" 2>/dev/null || cp "$tmp" "$json_file"

log "saved $json_file"

if [[ "$http_code" != "200" ]]; then
  cat "$tmp" >&2
  exit 1
fi

api_error="$(jq -r '.error // empty' "$tmp")"

if [[ -n "$api_error" && "$api_error" != "null" ]]; then
  jq . "$tmp" >&2
  exit 1
fi

image_base64="$(
  jq -r '.data[0].b64_json // empty' "$tmp"
)"

[[ -n "$image_base64" && "$image_base64" != "null" ]] \
  || die "No image found, saved response: $json_file"

printf '%s' "$image_base64" \
  | base64 --decode > "$image_file"

log "saved $image_file"

jq -r \
  --arg image_input_price "$image_input_price" \
  --arg image_cached_price "$image_cached_price" \
  --arg image_output_price "$image_output_price" \
  --arg text_input_price "$text_input_price" \
  --arg text_cached_price "$text_cached_price" \
  --arg text_output_price "$text_output_price" \
  '
    .usage as $u

    | ($u.input_tokens // 0) as $input
    | ($u.input_tokens_details.cached_tokens // 0) as $cached
    | ($input - $cached) as $fresh
    | ($u.output_tokens // 0) as $output

    | ($u.input_tokens_details.image_tokens // 0) as $image_input
    | ($u.input_tokens_details.text_tokens // ($fresh - $image_input)) as $text_input

    | ($u.output_tokens_details.image_tokens // $output) as $image_output
    | ($u.output_tokens_details.text_tokens // ($output - $image_output)) as $text_output

    | (
        (
          $image_input * ($image_input_price | tonumber)
          + $cached * ($image_cached_price | tonumber)
          + $image_output * ($image_output_price | tonumber)
          + $text_input * ($text_input_price | tonumber)
          + $text_output * ($text_output_price | tonumber)
        ) / 1000000
      ) as $cost

    | "tokens input=\($input) cached=\($cached) output=\($output) total=\($u.total_tokens // 0)"
      + "\n"
      + "tokens image_input=\($image_input) text_input=\($text_input) image_output=\($image_output) text_output=\($text_output)"
      + "\n"
      + (
          if (
            $image_input_price == "0"
            and $text_input_price == "0"
            and $image_output_price == "0"
          ) then
            "cost unknown"
          else
            "cost $\($cost)"
          end
        )
  ' "$tmp" | while IFS= read -r line; do
    log "$line"
  done

printf '%s\n' "$image_file"
