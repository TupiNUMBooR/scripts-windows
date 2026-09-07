#!/usr/bin/env bash
set -Eeuo pipefail
# ask-tts.sh

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
OPENAI_TTS_MODEL="${OPENAI_TTS_MODEL:-gpt-4o-mini-tts}"
OPENAI_TTS_VOICE="${OPENAI_TTS_VOICE:-marin}"
OPENAI_TTS_SPEED="${OPENAI_TTS_SPEED:-1.0}"
OPENAI_TTS_INSTRUCTIONS="${OPENAI_TTS_INSTRUCTIONS:-}"
OPENAI_TTS_PRICE_PER_MINUTE="${OPENAI_TTS_PRICE_PER_MINUTE:-0.015}"

ENDPOINT_HOST="api.openai.com"
ENDPOINT_PATH="/v1/audio/speech"
ENDPOINT_URL="https://${ENDPOINT_HOST}${ENDPOINT_PATH}"

MAX_CHARS="${MAX_CHARS:-4096}"

PAID_PHASE=0

# region functions

usage() {
  cat <<EOF
$SCRIPT_NAME — synthesizes speech with the OpenAI audio API.

Sends text and voice settings to the speech endpoint and writes the returned
audio in the format selected by the output filename extension. Request data,
responses, and estimated cost are stored in configured files.

Usage:
  $SCRIPT_NAME <output_file> <text>
  $SCRIPT_NAME -h|--help

Arguments:
  output_file  Audio file to create: mp3, opus, aac, flac, wav, or pcm.
  text         Text to synthesize.

Environment:
  .env                         Optional repository-root configuration loaded when present.
  OPENAI_API_KEY               Required OpenAI API key.
  OPENAI_TTS_INSTRUCTIONS      Optional voice/style instructions.
  OPENAI_TTS_MODEL             TTS model. Default: gpt-4o-mini-tts
  OPENAI_TTS_PRICE_PER_MINUTE  Price per audio minute. Default: 0.015
  OPENAI_TTS_SPEED             Speech speed. Default: 1.0
  OPENAI_TTS_VOICE             Voice. Default: marin
  ASK_AI_DIR                   Request/response directory. Default: ./.ask-ai
  COST_FILE                    Cost log file. Default: ./cost.txt
  MAX_CHARS                    Maximum text characters. Default: 4096

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
  $SCRIPT_NAME voiceover.mp3 "Text to synthesize"

More info:
  https://developers.openai.com/api/docs/guides/text-to-speech
  https://www.openai.fm/
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

audio_format_from_file() {
  local file="$1"
  local ext="${file##*.}"

  [[ "$file" != "$ext" ]] \
    || die 65 "Output file must have an extension"

  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
    mp3|opus|aac|flac|wav|pcm)
      printf '%s\n' "$ext"
      ;;
    *)
      die 65 "Unsupported audio extension: .$ext"
      ;;
  esac
}

save_json_pretty_or_raw() {
  local src="$1"
  local dst="$2"

  jq . "$src" > "$dst" 2>/dev/null || cp "$src" "$dst"
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

append_tts_cost() {
  local audio_file="$1"

  if ! command -v ffprobe >/dev/null 2>&1; then
    log "[WARN] TTS price unavailable: ffprobe missing"
    return
  fi

  local duration_seconds
  duration_seconds="$(
    ffprobe \
      -v error \
      -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 \
      "$audio_file"
  )"

  if [[ -z "$duration_seconds" ]]; then
    log "[WARN] TTS price unavailable: empty duration"
    return
  fi

  local cost
  cost="$(
    awk \
      -v seconds="$duration_seconds" \
      -v price_per_minute="$OPENAI_TTS_PRICE_PER_MINUTE" \
      'BEGIN {
        printf "%.8f", seconds / 60 * price_per_minute
      }'
  )"

  append_cost "tts" "$cost"
}

# endregion

main() {
  trap on_error ERR
  need_commands jq curl awk sed

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  (($# == 2)) || {
    usage >&2
    printf '\n' >&2
    die 2 "Expected output file and text"
  }

  local output_file="$1"
  local text="$2"

  if [[ -e "$output_file" ]]; then
    log "[WARN] Output already exists: $output_file"
    exit 21
  fi

  [[ -n "${output_file//[[:space:]]/}" ]] \
    || die 66 "Empty output file"

  [[ -n "${text//[[:space:]]/}" ]] \
    || die 66 "Empty text"

  ((${#text} <= MAX_CHARS)) \
    || die 65 "Text too long (${#text} > $MAX_CHARS)"

  local output_format
  output_format="$(audio_format_from_file "$output_file")"

  mkdir -p "$(dirname "$output_file")"
  mkdir -p "$ASK_AI_DIR"

  local stamp
  stamp="$(timestamp_ms)"

  local safe_text
  safe_text="$(safe_filename_part "$text")"

  local base="${ASK_AI_DIR}/${stamp}_${safe_text:-tts}"
  local request_file="${base}_request.json"
  local response_error_file="${base}_response_error.json"

  local payload
  payload="$(
    jq -n \
      --arg model "$OPENAI_TTS_MODEL" \
      --arg input "$text" \
      --arg voice "$OPENAI_TTS_VOICE" \
      --arg response_format "$output_format" \
      --argjson speed "$OPENAI_TTS_SPEED" \
      --arg instructions "$OPENAI_TTS_INSTRUCTIONS" \
      '{
        model: $model,
        input: $input,
        voice: $voice,
        response_format: $response_format,
        speed: $speed
      }
      + (
        if $instructions == "" then
          {}
        else
          { instructions: $instructions }
        end
      )'
  )"

  jq . <<<"$payload" > "$request_file"

  local tmp_response
  tmp_response="$(mktemp)"
  trap "rm -f '$tmp_response'" EXIT

  log "request tts: model=$OPENAI_TTS_MODEL voice=$OPENAI_TTS_VOICE format=$output_format speed=$OPENAI_TTS_SPEED chars=${#text}"

  if [[ -n "$OPENAI_TTS_INSTRUCTIONS" ]]; then
    log "instructions_chars=${#OPENAI_TTS_INSTRUCTIONS}"
  fi

  PAID_PHASE=1

  local http_code
  http_code="$(
    curl -sS -o "$tmp_response" -w '%{http_code}' \
      "$ENDPOINT_URL" \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload"
  )"

  if [[ "$http_code" != "200" ]]; then
    save_json_pretty_or_raw "$tmp_response" "$response_error_file"

    log "[ERROR] POST ${ENDPOINT_HOST}${ENDPOINT_PATH} <- $http_code"
    log "[ERROR] request_json=$request_file"
    log "[ERROR] response_json=$response_error_file"

    cat "$tmp_response" >&2

    die 69 "Request failed with HTTP code $http_code"
  fi

  cp "$tmp_response" "$output_file"

  [[ -s "$output_file" ]] \
    || die 65 "Empty audio file: $output_file"

  append_tts_cost "$output_file"
}

main "$@"
