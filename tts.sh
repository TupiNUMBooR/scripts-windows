#!/usr/bin/env bash
set -euo pipefail

. .env

API_KEY="${OPENAI_API_KEY:?Укажи OPENAI_API_KEY в окружении}"

command -v curl >/dev/null || { echo "curl не найден" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq не найден" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: tts.sh [-v voice]

Reads text from STDIN and outputs MP3 to STDOUT.

Options:
  -v voice   Voice name (default: alloy)
  -h         Show this help

Available voices:
  alloy     – neutral, default
  nova      – female, clear, great for shorts
  shimmer   – female, soft, airy
  fable     – female, warm, storytelling
  echo      – male
  onyx      – male, deep, radio-like
EOF
  exit 1
}

VOICE="alloy"

while getopts ":v:h" opt; do
  case "$opt" in
    v) VOICE="$OPTARG" ;;
    h) usage ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage ;;
  esac
done
shift $((OPTIND - 1))
echo "Using voice: $VOICE" >&2

TEXT="$(cat)"

if [[ -z "${TEXT// }" ]]; then
  echo "Пустой ввод" >&2
  exit 1
fi

MAX_CHARS=3000
if (( ${#TEXT} > MAX_CHARS )); then
  echo "Текст слишком длинный (${#TEXT} > $MAX_CHARS)" >&2
  exit 1
fi

RESPONSE=$(mktemp)

HTTP_CODE=$(curl -sS https://api.openai.com/v1/audio/speech \
  -w "%{http_code}" \
  -o "$RESPONSE" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg model "gpt-4o-mini-tts" \
        --arg voice "$VOICE" \
        --arg input "$TEXT" \
        '{
          model: $model,
          voice: $voice,
          input: $input
        }'
      )"
)

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "Ошибка API (HTTP $HTTP_CODE):" >&2
  cat "$RESPONSE" >&2
  rm "$RESPONSE"
  exit 1
fi

cat "$RESPONSE"
rm "$RESPONSE"
