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

SRT="${AUDIO%.*}-2.srt"
ID_FILE=".tmp/${AUDIO%.*}-id.txt"


if [[ -f "$SRT" ]]; then
  echo "Fixed SRT already exists: $SRT"
else
  RAW_TXT=$(jq -Rs . < "$TXT" | sed 's/^"//; s/"$//')

  #
  # === FILE ID CACHING ===
  #

  # If cache exists → load ID
  if [[ -f "$ID_FILE" ]]; then
    echo "[1] Found cached ID: $ID_FILE"
    AUDIO_FILE_ID=$(cat "$ID_FILE")

    # Validate cached ID
    if [[ -n "$AUDIO_FILE_ID" && "$AUDIO_FILE_ID" != "null" ]]; then
      echo "Using cached ID: $AUDIO_FILE_ID"
    else
      echo "Cached ID invalid — reuploading…"
      rm -f "$ID_FILE"
      AUDIO_FILE_ID=""
    fi
  fi

  # Upload only if no valid cached ID
  if [[ -z "${AUDIO_FILE_ID:-}" ]]; then
    echo "[1] Uploading audio file…"

    UPLOAD_RESPONSE=$(curl https://api.openai.com/v1/files \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -F "file=@$AUDIO" \
      -F "purpose=vision")

    # Check API errors
    if echo "$UPLOAD_RESPONSE" | jq -e '.error != null' >/dev/null; then
      echo "File upload error:" >&2
      echo "$UPLOAD_RESPONSE" | jq -r '.error.message' >&2
      exit 1
    fi

    AUDIO_FILE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

    if [[ -z "$AUDIO_FILE_ID" || "$AUDIO_FILE_ID" == "null" ]]; then
      echo "ERROR: Upload succeeded but no file ID returned." >&2
      exit 1
    fi

    echo "$AUDIO_FILE_ID" > "$ID_FILE"
    echo "Uploaded and cached file ID: $AUDIO_FILE_ID"
  fi


  #
  # === ALIGNMENT STEP ===
  #
  echo "[2] Aligning audio + lyrics → SRT…"

  RESPONSE=$(curl https://api.openai.com/v1/responses \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "model": "gpt-4.1",
  "input": [
    {
      "role": "system",
      "content": "You are an expert audio forced-aligner. Given an audio file and the correct lyrics, you generate accurate SRT subtitles with correct timestamps."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "input_file",
          "input_file_id": "$AUDIO_FILE_ID"
        },
        {
          "type": "input_text",
          "input_text": "===lyrics===\n$RAW_TXT\n\nGenerate a perfectly aligned SRT file."
        }
      ]
    }
  ]
}
EOF
)

  # API error checking
  if echo "$RESPONSE" | jq -e '.error != null' >/dev/null; then
    echo "OpenAI API error:" >&2
    echo "$RESPONSE" | jq -r '.error.message' >&2
    exit 1
  fi

  echo "$RESPONSE" | jq -r '.output[0].content[0].text' > "$SRT"
  echo "DONE → $SRT"
fi
