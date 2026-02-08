#!/usr/bin/env bash
set -euo pipefail

d="$(date +%m%d-%H%M)"

word="$(ask-ai.sh "Придумай рандомное слово. Только одно слово, оно не должно быть слишком сложным или слишком обычным. Это слово для рубрики "интересные факты о...")"
echo "Слово: $word"

response=$(ask-fact.sh "$word")
echo "Ответ: $response"

echo "$response" | tts.sh > "$d.mp3"
echo "Озвучка сохранена в $d.mp3"
