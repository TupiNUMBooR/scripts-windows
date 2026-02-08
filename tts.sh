#!/usr/bin/env bash
set -euo pipefail

. .env

API_KEY="${OPENAI_API_KEY:?Укажи OPENAI_API_KEY в окружении}"

command -v curl >/dev/null || { echo "curl не найден"; exit 1; }
command -v jq   >/dev/null || { echo "jq не найден"; exit 1; }

TEXT=$(cat)

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
  -d "{
    \"model\": \"gpt-4o-mini-tts\",
    \"voice\": \"alloy\",
    \"input\": $(jq -Rs . <<< "$TEXT")
  }"
)

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "Ошибка API (HTTP $HTTP_CODE):" >&2
  cat "$RESPONSE" >&2
  rm "$RESPONSE"
  exit 1
fi

cat "$RESPONSE"
rm "$RESPONSE"
