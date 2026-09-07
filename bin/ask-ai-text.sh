#!/usr/bin/env bash
set -Eeuo pipefail
# ask-ai-text.sh

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
OPENAI_TEXT_MODEL="${OPENAI_TEXT_MODEL:-gpt-5.6-luna}"

ENDPOINT_HOST="api.openai.com"
ENDPOINT_PATH="/v1/responses"
ENDPOINT_URL="https://${ENDPOINT_HOST}${ENDPOINT_PATH}"

MAX_CHARS="${MAX_CHARS:-20000}"

PAID_PHASE=0

# region functions

usage() {
  cat <<EOF
$SCRIPT_NAME — sends text to the OpenAI text API.

Reads text from a file, a literal argument, or standard input.
Writes only the assistant response text to standard output and stores request
metadata, responses, and cost data in configured files.

Usage:
  $SCRIPT_NAME [text_file|text]
  $SCRIPT_NAME -h|--help

Input:
  With one argument, the value is treated as a file when that file exists;
  otherwise it is treated as literal text. With no arguments, text is read
  from standard input.

Environment:
  .env               Optional repository-root configuration loaded when present.
  OPENAI_API_KEY     Required OpenAI API key.
  OPENAI_TEXT_MODEL  Text model. Default: gpt-5.6-luna
  ASK_AI_DIR         Request/response directory. Default: ./.ask-ai
  COST_FILE          Cost log file. Default: ./cost.txt
  MAX_CHARS          Maximum input characters. Default: 20000

Exit codes:
  0    Success.
  2    Invalid command-line arguments.
  65   Invalid input data.
  66   Required input is missing.
  69   API is unavailable.
  127  Required command is unavailable.
  13   Paid API phase error.

Examples:
  $SCRIPT_NAME prompt.txt
  $SCRIPT_NAME 'Explain why the sky is blue.'
  printf '%s\n' 'Explain why the sky is blue.' | $SCRIPT_NAME

More info:
  https://developers.openai.com/api/docs/guides/text?lang=curl
  https://developers.openai.com/api/docs/pricing
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

save_json_pretty_or_raw() {
  local src="$1"
  local dst="$2"

  jq . "$src" > "$dst" 2>/dev/null || cp "$src" "$dst"
}

read_input() {
  if [[ $# -eq 0 ]]; then
    cat
    return
  fi

  if [[ $# -eq 1 && "$1" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ $# -eq 1 && "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ $# -eq 1 && -f "$1" ]]; then
    cat "$1"
    return
  fi

  printf '%s' "$*"
}

load_model_prices() {
  # model               input   cached   output
  case "$OPENAI_TEXT_MODEL" in
    gpt-5.6-sol)   echo " 5.00  0.50      30.00" ;;
    gpt-5.6-terra) echo " 2.50  0.25      15.00" ;;
    gpt-5.6-luna)  echo " 1.00  0.10       6.00" ;;
    gpt-5.5)       echo " 5.00  0.50      30.00" ;;
    gpt-5.5-pro)   echo "30.00  0        180.00" ;;
    gpt-5.4)       echo " 2.50  0.25      15.00" ;;
    gpt-5.4-mini)  echo " 0.75  0.075      4.50" ;;
    gpt-5.4-nano)  echo " 0.20  0.02       1.25" ;;
    gpt-5.4-pro)   echo "30.00  0        180.00" ;;
    gpt-4o)        echo " 2.50  1.25      10.00" ;;
    *)             echo " 0     0          0   "
                   log "[WARN] Price unavailable for model: $OPENAI_TEXT_MODEL" ;;
  esac
}

extract_output_text() {
  local response_file="$1"

  jq -r '
    .output_text //
    (
      [
        .output[]?
        | select(.type == "message")
        | .content[]?
        | select(.type == "output_text")
        | .text
      ]
      | join("\n\n")
    )
  ' "$response_file"
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

  local input_price
  local cached_price
  local output_price

  read -r input_price cached_price output_price < <(load_model_prices)

  jq -r \
    --arg input_price "$input_price" \
    --arg cached_price "$cached_price" \
    --arg output_price "$output_price" \
    '
      if ($input_price == "0" and $cached_price == "0" and $output_price == "0") then
        empty
      else
        .usage as $u

        | ($u.input_tokens // 0) as $input
        | ($u.input_tokens_details.cached_tokens // 0) as $cached
        | ($input - $cached) as $fresh
        | ($u.output_tokens // 0) as $output

        | (
            (
              $fresh * ($input_price | tonumber)
              + $cached * ($cached_price | tonumber)
              + $output * ($output_price | tonumber)
            ) / 1000000
          )
      end
    ' "$response_file"
}

extract_and_append_cost() {
  local response_file="$1"

  local cost
  cost="$(extract_cost "$response_file")"

  if [[ -n "$cost" ]]; then
    append_cost "text" "$cost"
  fi
}

# endregion

main() {
  trap on_error ERR

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  need_commands jq curl
  [[ -n "$OPENAI_API_KEY" ]] || die 66 "OPENAI_API_KEY is not set"

  local input_text
  input_text="$(read_input "$@")"

  [[ -n "${input_text//[[:space:]]/}" ]] || die 66 "Empty text input"
  ((${#input_text} <= MAX_CHARS)) || die 65 "Text input too long (${#input_text} > $MAX_CHARS)"

  mkdir -p "$ASK_AI_DIR"

  local stamp
  stamp="$(timestamp_ms)"

  local request_file="${ASK_AI_DIR}/${stamp}_request.json"
  local response_file="${ASK_AI_DIR}/${stamp}_response.json"

  local payload
  payload="$(
    jq -n \
      --arg model "$OPENAI_TEXT_MODEL" \
      --arg input "$input_text" \
      '{
        model: $model,
        input: $input
      }'
  )"

  jq . <<<"$payload" > "$request_file"

  local tmp_response
  tmp_response="$(mktemp)"
  trap "rm -f '$tmp_response'" EXIT

  log "request text: model=$OPENAI_TEXT_MODEL chars=${#input_text}"

  PAID_PHASE=1

  local http_code
  http_code="$(
    curl -sS -o "$tmp_response" -w '%{http_code}' \
      "$ENDPOINT_URL" \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload"
  )"

  save_json_pretty_or_raw "$tmp_response" "$response_file"

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

  local text
  text="$(extract_output_text "$tmp_response")"

  [[ -n "${text//[[:space:]]/}" && "$text" != "null" ]] || die 65 "No output text found, saved response: $response_file"

  extract_and_append_cost "$tmp_response"

  printf '%s\n' "$text"
}

main "$@"
