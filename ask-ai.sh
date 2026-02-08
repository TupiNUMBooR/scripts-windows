#!/usr/bin/env bash
set -euo pipefail

. .env

API_KEY="${OPENAI_API_KEY:?Укажи OPENAI_API_KEY в окружении}"

command -v curl >/dev/null || { echo "curl не найден" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq не найден" >&2; exit 1; }

SYSTEM_PROMPT=""

# opts
while getopts ":s:" opt; do
  case "$opt" in
    s) SYSTEM_PROMPT="$OPTARG" ;;
    *)
      echo "Использование: $0 [-s system_prompt] [prompt]" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

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

MESSAGES=$(jq -n \
  --arg system "$SYSTEM_PROMPT" \
  --arg user "$PROMPT" '
  [
    (select($system != "") | {role:"system", content:$system}),
    {role:"user", content:$user}
  ]
')

HTTP_CODE=$(curl -sS https://api.openai.com/v1/chat/completions \
  -w "%{http_code}" \
  -o "$RESPONSE" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --argjson messages "$MESSAGES" '{
        model: "gpt-5-mini",
        messages: $messages
      }')"
)

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "Ошибка API (HTTP $HTTP_CODE)" >&2
  cat "$RESPONSE" >&2
  rm "$RESPONSE"
  exit 1
fi

jq -r '.choices[0].message.content' "$RESPONSE"
rm "$RESPONSE"
