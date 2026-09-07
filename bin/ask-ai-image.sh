#!/usr/bin/env bash
set -Eeuo pipefail
# ask-ai-image.sh

SCRIPT_NAME="$(basename "$0")"

# Load project configuration from the repository root when present.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
if [[ -f "$PROJECT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/.env"
fi

ASK_AI_DIR="${ASK_AI_DIR:-./.ask-ai}"
COST_FILE="${COST_FILE:-./cost.txt}"

OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_IMAGE_MODEL="${OPENAI_IMAGE_MODEL:-gpt-image-2}"
OPENAI_IMAGE_SIZE="${OPENAI_IMAGE_SIZE:-${WIDTH:-1536}x${HEIGHT:-1024}}"
OPENAI_IMAGE_QUALITY="${OPENAI_IMAGE_QUALITY:-low}"

ENDPOINT_HOST="api.openai.com"
ENDPOINT_PATH="/v1/images/generations"
ENDPOINT_URL="https://${ENDPOINT_HOST}${ENDPOINT_PATH}"

MAX_CHARS="${MAX_CHARS:-4000}"

PAID_PHASE=0

# region functions

usage() {
  cat <<EOF
$SCRIPT_NAME — generates one image with the OpenAI image API.

Sends a text prompt, decodes the returned image, and writes it in the format
selected by the output filename extension. Request metadata, responses, and
cost data are stored in configured files.

Usage:
  $SCRIPT_NAME <output_file> <prompt>
  $SCRIPT_NAME -h|--help

Arguments:
  output_file  Image file to create: png, webp, jpg, or jpeg.
  prompt       Image generation prompt.

Environment:
  .env                   Optional repository-root configuration loaded when present.
  OPENAI_API_KEY        Required OpenAI API key.
  OPENAI_IMAGE_MODEL    Image model. Default: gpt-image-2
  OPENAI_IMAGE_QUALITY  Image quality. Default: low
  OPENAI_IMAGE_SIZE     Image size. Default: WIDTHxHEIGHT or 1536x1024
  ASK_AI_DIR            Request/response directory. Default: ./.ask-ai
  COST_FILE             Cost log file. Default: ./cost.txt
  MAX_CHARS             Maximum prompt characters. Default: 4000

Exit codes:
  0    Success.
  2    Invalid command-line arguments.
  65   Invalid input data.
  66   Required input is missing.
  69   API is unavailable.
  127  Required command is unavailable.
  13   Paid API phase error. 
  21   Output already exists. 

Example:
  $SCRIPT_NAME image.png "vertical surreal cozy occult background, no text"

More info:
  https://developers.openai.com/api/docs/guides/image-generation
  https://developers.openai.com/api/docs/pricing#image-tokens
EOF
}

log() {
  printf '[%s] [%s] %s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$SCRIPT_NAME" \
    "$*" >&2
}

die() {
  local code="$1"
  shift

  if ((PAID_PHASE)); then
    log "[ERROR] Exit 13 (was $code): $*"
    exit 13
  fi

  log "[ERROR] Exit $code: $*"
  exit "$code"
}

on_error() {
  local code=$?

  trap - ERR

  if ((PAID_PHASE && code != 13)); then
    log "[ERROR] Exit 13 (was $code)"
    exit 13
  fi

  exit "$code"
}

need_commands() {
  for name in "$@"; do
    command -v "$name" >/dev/null 2>&1 \
      || die 127 "Missing executable: $name"
  done
}

timestamp_ms() {
  date -u +"%Y%m%d_%H%M%S_%3N"
}

safe_filename_part() {
  printf '%s' "$1" \
    | tr '\n\r\t' ' ' \
    | cut -c 1-80 \
    | sed 's/[^[:alnum:]_.-]/-/g; s/-\+/-/g; s/^-//; s/-$//'
}

image_format_from_file() {
  local file="$1"
  local ext="${file##*.}"

  [[ "$file" != "$ext" ]] \
    || die 65 "Output file must have an extension"

  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
    png|webp)
      printf '%s\n' "$ext"
      ;;
    jpg|jpeg)
      printf '%s\n' "jpeg"
      ;;
    *)
      die 65 "Unsupported image extension: .$ext"
      ;;
  esac
}

save_response_json() {
  local src="$1"
  local dst="$2"

  jq 'del(.data[]?.b64_json)' "$src" > "$dst" 2>/dev/null \
    || cp "$src" "$dst"
}

load_model_prices() {
  # model                  image input cached output   text input cached output
  case "$OPENAI_IMAGE_MODEL" in
    gpt-image-2)       echo " 8.00  2.00  30.00   5.00  1.25   0.00" ;;
    gpt-image-1.5)     echo " 8.00  2.00  32.00   5.00  1.25  10.00" ;;
    gpt-image-1-mini)  echo " 2.50  0.25   8.00   2.00  0.20   0.00" ;;
    *)                 echo " 0     0      0      0     0      0"
                       log "[WARN] Price unavailable for model: $OPENAI_IMAGE_MODEL" ;;
  esac
}

append_cost() {
  local type="$1"
  local cost="$2"
  local file="${3:-$COST_FILE}"
  local formatted

  mkdir -p "$(dirname "$file")"
  printf -v formatted '%.8f' "$cost"
  printf '%s %s\n' "$type" "$formatted" >> "$file"
  log "cost: $type $formatted"
}

extract_cost() {
  local response_file="$1"

  local image_input_price
  local image_cached_price
  local image_output_price
  local text_input_price
  local text_cached_price
  local text_output_price

  read -r \
    image_input_price \
    image_cached_price \
    image_output_price \
    text_input_price \
    text_cached_price \
    text_output_price \
    < <(load_model_prices)

  jq -r \
    --arg image_input_price "$image_input_price" \
    --arg image_cached_price "$image_cached_price" \
    --arg image_output_price "$image_output_price" \
    --arg text_input_price "$text_input_price" \
    --arg text_cached_price "$text_cached_price" \
    --arg text_output_price "$text_output_price" \
    '
      if (
        $image_input_price == "0"
        and $text_input_price == "0"
        and $image_output_price == "0"
      ) then
        empty
      else
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
          )
      end
    ' "$response_file"
}

append_response_cost() {
  local cost
  cost="$(extract_cost "$1")"

  [[ -n "$cost" ]] && append_cost "image" "$cost"
}

# endregion

main() {
  trap on_error ERR
  need_commands jq curl base64 sed

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  (($# == 2)) || {
    usage >&2
    printf '\n' >&2
    die 2 "Expected output file and prompt"
  }

  local output_file="$1"
  local prompt="$2"

  if [[ -e "$output_file" ]]; then
    log "[WARN] Output already exists: $output_file"
    exit 21
  fi

  [[ -n "${output_file//[[:space:]]/}" ]] \
    || die 66 "Empty output file"

  [[ -n "${prompt//[[:space:]]/}" ]] \
    || die 66 "Empty prompt"

  ((${#prompt} <= MAX_CHARS)) \
    || die 65 "Prompt too long (${#prompt} > $MAX_CHARS)"

  local output_format
  output_format="$(image_format_from_file "$output_file")"

  mkdir -p "$(dirname "$output_file")"
  mkdir -p "$ASK_AI_DIR"

  local stamp
  stamp="$(timestamp_ms)"

  local safe_prompt
  safe_prompt="$(safe_filename_part "$prompt")"

  local base="${ASK_AI_DIR}/${stamp}_${safe_prompt:-image}"
  local request_file="${base}_request.json"
  local response_file="${base}_response.json"

  local payload
  payload="$(
    jq -n \
      --arg model "$OPENAI_IMAGE_MODEL" \
      --arg prompt "$prompt" \
      --arg size "$OPENAI_IMAGE_SIZE" \
      --arg quality "$OPENAI_IMAGE_QUALITY" \
      --arg format "$output_format" \
      '{
        model: $model,
        prompt: $prompt,
        size: $size,
        quality: $quality,
        output_format: $format
      }'
  )"

  jq . <<<"$payload" > "$request_file"

  local tmp_response
  tmp_response="$(mktemp)"
  trap "rm -f '$tmp_response'" EXIT

  log "request image: model=$OPENAI_IMAGE_MODEL size=$OPENAI_IMAGE_SIZE quality=$OPENAI_IMAGE_QUALITY format=$output_format chars=${#prompt}"

  PAID_PHASE=1

  local http_code
  http_code="$(
    curl -sS -o "$tmp_response" -w '%{http_code}' \
      "$ENDPOINT_URL" \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload"
  )"

  save_response_json "$tmp_response" "$response_file"

  if [[ "$http_code" != "200" ]]; then
    log "[ERROR] POST ${ENDPOINT_HOST}${ENDPOINT_PATH} <- $http_code"
    log "[ERROR] request_json=$request_file"
    log "[ERROR] response_json=$response_file"
    cat "$tmp_response" >&2
    die 69 "Request failed with HTTP code $http_code"
  fi

  local api_error
  api_error="$(jq -r '.error // empty' "$tmp_response")"

  if [[ -n "$api_error" && "$api_error" != "null" ]]; then
    log "[ERROR] API error"
    log "[ERROR] request_json=$request_file"
    log "[ERROR] response_json=$response_file"
    jq . "$tmp_response" >&2
    die 69 "API error: $api_error"
  fi

  local image_base64
  image_base64="$(jq -r '.data[0].b64_json // empty' "$tmp_response")"

  [[ -n "$image_base64" && "$image_base64" != "null" ]] \
    || die 65 "No image found, saved response: $response_file"

  printf '%s' "$image_base64" \
    | base64 --decode \
    > "$output_file"

  append_response_cost "$tmp_response"
}

main "$@"
