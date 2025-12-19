#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <audio> <lyrics.txt>"
  exit 1
fi

. "$(dirname "$0")/.env"

AUDIO="$1"
TXT="$2"

if [[ ! -f "$AUDIO" ]]; then
  echo "Audio file not found: $AUDIO"
  exit 1
fi

if [[ ! -f "$TXT" ]]; then
  echo "Lyrics TXT file not found: $TXT"
  exit 1
fi

mkdir -p .tmp

TRANSCRIPTED=".tmp/${AUDIO%.*}-raw.srt"
FIXED="${AUDIO%.*}.srt"

if [[ -f "$TRANSCRIPTED" ]]; then
  echo "Fixed SRT already exists: $TRANSCRIPTED"
else
  echo "[1] Transcribing audio with Whisper..."
  curl https://api.openai.com/v1/audio/transcriptions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: multipart/form-data" \
    -F "file=@${AUDIO}" \
    -F "model=whisper-1" \
    -F "response_format=srt" \
    -o "$TRANSCRIPTED"
fi

if [[ -f "$FIXED" ]]; then
  echo "Fixed SRT already exists: $FIXED"
else
  echo "[2] Requesting corrected SRT..."

  RAW_SRT=$(jq -Rs . < "$TRANSCRIPTED" | sed 's/^"//; s/"$//')
  RAW_TXT=$(jq -Rs . < "$TXT" | sed 's/^"//; s/"$//')

  JSON_PAYLOAD=$(cat <<EOF
{
  "model": "gpt-4.1",
  "input": [
    {
      "role": "system",
      "content": "You are a subtitle correction tool. You will be provided with SRT and TXT files. Keep all timestamps in the SRT exactly as-is. Replace each subtitle block's text with lines from the TXT lyrics, in order. Use TXT as the only correct text source. Do not alter timestamps or block structure. Output only a corrected SRT file."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "===transcripted.srt===\n$RAW_SRT\n\n===lyrics.txt===\n$RAW_TXT"
        }
      ]
    }
  ]
}
EOF
)

  RESPONSE=$(curl https://api.openai.com/v1/responses \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

  if echo "$RESPONSE" | jq -e '.error != null' >/dev/null; then
    echo "OpenAI API error:" >&2
    echo "$RESPONSE" | jq -r '.error.message' >&2
    exit 1
  fi

  echo "$RESPONSE" | jq -r '.output[0].content[0].text' > "$FIXED"

  echo "DONE!"
  echo "Fixed SRT saved to: $FIXED"
fi
