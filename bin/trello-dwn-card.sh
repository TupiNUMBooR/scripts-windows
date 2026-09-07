#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 CARD_ID_OR_URL"
  exit 1
fi

CARD_INPUT="$1"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/.env"

API="https://api.trello.com/1"
OUT_DIR="./trello-backuper"

if [[ "$CARD_INPUT" == *"/c/"* ]]; then
  CARD_ID="${CARD_INPUT#*/c/}"
  CARD_ID="${CARD_ID%%/*}"
  CARD_ID="${CARD_ID%%\?*}"
else
  CARD_ID="$CARD_INPUT"
fi

OUT_FILE="$OUT_DIR/$CARD_ID.md"

mkdir -p "$OUT_DIR"

echo "[*] Fetching card $CARD_ID..."

CARD=$(
  curl -s \
    "$API/cards/$CARD_ID?fields=name,shortUrl&key=$TRELLO_KEY&token=$TRELLO_TOKEN"
)

if ! echo "$CARD" | jq empty >/dev/null 2>&1; then
  echo "[!] Error: Failed to parse card JSON response"
  echo "$CARD"
  exit 1
fi

CARD_NAME=$(jq -r '.name' <<<"$CARD")
CARD_URL=$(jq -r '.shortUrl' <<<"$CARD")

echo "[*] Fetching comments..."

RESPONSE=$(
  curl -s \
    "$API/cards/$CARD_ID/actions?filter=commentCard&key=$TRELLO_KEY&token=$TRELLO_TOKEN"
)

if ! echo "$RESPONSE" | jq empty >/dev/null 2>&1; then
  echo "[!] Error: Failed to parse comments JSON response"
  echo "$RESPONSE"
  exit 1
fi

echo "[*] Converting to markdown..."

{
  printf '# [%s](%s)\n\n' "$CARD_NAME" "$CARD_URL"

  echo "$RESPONSE" \
    | jq -r '
        reverse[]
        | .date as $date
        | ($date
            | sub("\\.[0-9]+Z$"; "Z")
            | fromdateiso8601
            | strftime("%u")
          ) as $weekday
        | ($date | split("T")[0]) as $day
        | ($date
            | split("T")[1]
            | split(".")[0]
            | gsub(":"; "-")
          ) as $time
        | "### \($day)d\($weekday) \($time)\n\n\(.data.text)\n"
      '
} > "$OUT_FILE"

echo "[✓] Done: $OUT_FILE"
