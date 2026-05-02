#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 CARD_ID"
  exit 1
fi

CARD_ID="$1"

source .env

API="https://api.trello.com/1"

mkdir -p tmp out

echo "[*] Fetching comments for card $CARD_ID..."

curl -s "$API/cards/$CARD_ID/actions?filter=commentCard&key=$TRELLO_KEY&token=$TRELLO_TOKEN" \
  | jq -r '.[] | [.date, .data.text] | @tsv' \
  > "tmp/$CARD_ID.tsv"

echo "[*] Converting to markdown..."

while IFS=$'\t' read -r date text; do
  day=$(echo "$date" | cut -d'T' -f1)
  file="out/$day.md"

  echo -e "\n$text" >> "$file"
done < "tmp/$CARD_ID.tsv"

echo "[✓] Done. Files in ./out/"
