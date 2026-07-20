#!/usr/bin/env bash
set -euo pipefail

: "${OPENAI_API_KEY:?}"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

need curl
need jq

SCRIPT_NAME="$(basename "$0")"
ENDPOINT_HOST="api.openai.com"
ENDPOINT_PATH="/v1/responses"
ENDPOINT_URL="https://${ENDPOINT_HOST}${ENDPOINT_PATH}"

OPENAI_TEXT_MODEL="${OPENAI_TEXT_MODEL:-gpt-5.4-mini}"
OUT_DIR="${OUT_DIR:-.}"
MAX_CHARS="${MAX_CHARS:-2000}"
SYSTEM_PROMPT=""

log() {
  printf '[%s] [%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$SCRIPT_NAME" "$*" >&2
}

usage() {
  cat >&2 <<EOF
Usage:
  $SCRIPT_NAME [-s system_prompt] [prompt...]
  $SCRIPT_NAME [-s system_prompt] < prompt.txt

Env:
  OPENAI_API_KEY      required
  OPENAI_TEXT_MODEL   default: gpt-5.4-mini
  OUT_DIR             default: .
  MAX_CHARS           default: 2000
EOF
  exit 1
}

while getopts ":s:h" opt; do
  case "$opt" in
    s) SYSTEM_PROMPT="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

PROMPT="${*:-$(cat)}"
[[ -n "${PROMPT//[[:space:]]/}" ]] || die "Empty prompt"
((${#PROMPT} <= MAX_CHARS)) || die "Prompt too long (${#PROMPT} > $MAX_CHARS)"

# https://developers.openai.com/api/docs/pricing
read -r input_price cached_price output_price < <(
  case "$OPENAI_TEXT_MODEL" in
    gpt-5.5)      echo "5.00 0.50 30.00" ;;
    gpt-5.5-pro)  echo "30.00 0 180.00" ;;
    gpt-5.4)      echo "2.50 0.25 15.00" ;;
    gpt-5.4-mini) echo "0.75 0.075 4.50" ;;
    gpt-5.4-nano) echo "0.20 0.02 1.25" ;;
    gpt-5.4-pro)  echo "30.00 0 180.00" ;;
    *)            echo "0 0 0" ;;
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
json_file="$OUT_DIR/response-${stamp}-${safe_name:-request}.json"

payload="$(
  jq -n \
    --arg model "$OPENAI_TEXT_MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$PROMPT" \
    '{
      model: $model,
      input:
        if $system == "" then
          [{ role: "user", content: $user }]
        else
          [
            { role: "system", content: $system },
            { role: "user", content: $user }
          ]
        end
    }'
)"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

log "request model=$OPENAI_TEXT_MODEL chars=${#PROMPT} json=$json_file"
log "POST ${ENDPOINT_HOST}${ENDPOINT_PATH} ->"

http_code="$(
  curl -sS -o "$tmp" -w '%{http_code}' \
    "$ENDPOINT_URL" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload"
)"

log "POST ${ENDPOINT_HOST}${ENDPOINT_PATH} <- $http_code"

jq . "$tmp" > "$json_file" 2>/dev/null || cp "$tmp" "$json_file"
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

text="$(
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
  ' "$tmp"
)"

[[ -n "$text" && "$text" != "null" ]] || die "No output text found, saved response: $json_file"

jq -r \
  --arg input_price "$input_price" \
  --arg cached_price "$cached_price" \
  --arg output_price "$output_price" \
  '
    .usage as $u
    | ($u.input_tokens // 0) as $input
    | ($u.input_tokens_details.cached_tokens // 0) as $cached
    | ($input - $cached) as $fresh
    | ($u.output_tokens // 0) as $output
    | (($fresh * ($input_price | tonumber)
      + $cached * ($cached_price | tonumber)
      + $output * ($output_price | tonumber)) / 1000000) as $cost
    | "tokens input=\($input) cached=\($cached) output=\($output) total=\($u.total_tokens // 0)"
      + "\n"
      + (
          if ($input_price == "0" and $cached_price == "0" and $output_price == "0") then
            "cost unknown"
          else
            "cost $\($cost)"
          end
        )
  ' "$tmp" | while IFS= read -r line; do log "$line"; done

printf '%s\n' "$text"
