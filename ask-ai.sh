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

curl -sS https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"gpt-5-mini\",
    \"messages\": [
      {\"role\": \"system\", \"content\": \"Отвечай кратко, одним интересным фактом.\"},
      {\"role\": \"user\", \"content\": $(jq -Rs . <<< \"$PROMPT\")}
    ]
  }" \
| jq -r '.choices[0].message.content'
