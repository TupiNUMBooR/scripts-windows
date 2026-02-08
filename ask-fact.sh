#!/usr/bin/env bash
set -euo pipefail

. .env

API_KEY="${OPENAI_API_KEY:?Укажи OPENAI_API_KEY в окружении}"

command -v curl >/dev/null || { echo "curl не найден" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq не найден" >&2; exit 1; }

# Ввод: либо аргумент, либо stdin
if [[ $# -gt 0 ]]; then
  PROMPT="$*"
else
  PROMPT="$(cat)"
fi

if [[ -z "${PROMPT// }" ]]; then
  echo "Пустой запрос" >&2
  exit 1
fi

MAX_CHARS=2000
if (( ${#PROMPT} > MAX_CHARS )); then
  echo "Запрос слишком длинный (${#PROMPT} > $MAX_CHARS)" >&2
  exit 1
fi

RESPONSE=$(mktemp)

HTTP_CODE=$(curl -sS https://api.openai.com/v1/chat/completions \
  -w "%{http_code}" \
  -o "$RESPONSE" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"gpt-5-mini\",
    \"messages\": [
      {\"role\": \"system\", \"content\": \"Напиши текст для озвучки в видео шортс-формата. Для каждой вещи, которую указал пользователь - приведи один любопытный факт. Требуемый формат ответа: Только текст ролика.\"},
      {
        \"role\": \"user\",
        \"content\": $(jq -Rs . <<< \"$PROMPT\")
      }
    ]
  }"
)

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "Ошибка API (HTTP $HTTP_CODE)" >&2
  cat "$RESPONSE" >&2
  rm "$RESPONSE"
  exit 1
fi

jq -r '.choices[0].message.content' "$RESPONSE"
rm "$RESPONSE"
