#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 CARD_ID"
  exit 1
fi

CARD_ID="$1"

source .env

API="https://api.trello.com/1"

OUT_DIR="./trello-backuper"

mkdir -p "$OUT_DIR"

echo "[*] Fetching comments for card $CARD_ID..."

RESPONSE=$(curl -s "$API/cards/$CARD_ID/actions?filter=commentCard&key=$TRELLO_KEY&token=$TRELLO_TOKEN")

if ! echo "$RESPONSE" | jq empty >/dev/null 2>&1; then
  echo "[!] Error: Failed to parse JSON response"
  echo "$RESPONSE"
  exit 1
fi

echo "$RESPONSE" \
  | jq -r 'reverse[] | [.date, .data.text] | @tsv' \
  > "$OUT_DIR/$CARD_ID.tsv"

echo "[*] Converting to markdown..."

while IFS=$'\t' read -r date text; do
  day=$(echo "$date" | cut -d'T' -f1)
  time=$(echo "$date" | cut -d'T' -f2 | cut -d'.' -f1)
  file="$OUT_DIR/$day-trello.md"

  echo -e "\n### $time\n\n$text" >> "$file"
done < "$OUT_DIR/$CARD_ID.tsv"

echo "[✓] Done. Files in $OUT_DIR/"
