#!/usr/bin/env bash
set -euo pipefail

: "${TELEGRAM_BOT_TOKEN:?}"

offset=0
api="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN"

while true; do
  resp="$(curl -s "$api/getUpdates?timeout=30&offset=$offset")"

  while read -r u; do
    offset=$(( $(jq -r '.update_id' <<<"$u") + 1 ))

    chat_id="$(jq -r '.message.chat.id' <<<"$u")"
    user_id="$(jq -r '.message.from.id' <<<"$u")"

    text=$(
      cat <<EOF
chat_id: $chat_id
user_id: $user_id
EOF
    )

    curl -s "$api/sendMessage" \
      -d chat_id="$chat_id" \
      --data-urlencode "text=$text" \
      >/dev/null
  done < <(echo "$resp" | jq -c '.result[]?')
done
