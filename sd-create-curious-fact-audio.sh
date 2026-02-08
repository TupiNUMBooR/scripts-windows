#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

# Basic deps + scripts availability
need tr
need wc

[[ -x "./ask-ai.sh" ]]   || die "ask-ai.sh not found or not executable (chmod +x ask-ai.sh)"
[[ -x "./ask-fact.sh" ]] || die "ask-fact.sh not found or not executable (chmod +x ask-fact.sh)"
[[ -x "./tts.sh" ]]      || die "tts.sh not found or not executable (chmod +x tts.sh)"

echo "=== Генерация любопытного факта и озвучки для рандомного слова - началась ==="

# Generate word
word="$(./ask-ai.sh 'Придумай рандомное слово. Только одно слово, оно не должно быть слишком сложным или слишком обычным. Это слово для рубрики "интересные факты о..."' \
  | tr -d '\r' \
  | tr -s '[:space:]' ' ' \
  | tr -d '[:space:]')"

[[ -n "$word" ]] || die "ask-ai.sh returned empty word"
# Keep only a single token (no spaces/newlines)
[[ "$word" == "${word%% *}" ]] || die "Word contains spaces: '$word'"
# Reasonable sanity: letters/digits/underscore/hyphen, 2..30 chars
[[ "$word" =~ ^[[:alnum:]_А-Яа-яЁё-]{2,30}$ ]] || die "Word looks invalid: '$word'"

echo "Слово: $word"

# Get fact response
response="$(./ask-fact.sh "$word" | tr -d '\r')"
[[ -n "$response" ]] || die "ask-fact.sh returned empty response"

# Length sanity (avoid weird giant dumps)
chars="$(printf '%s' "$response" | wc -c | tr -d ' ')"
(( chars >= 20 ))  || die "Response too short ($chars chars): '$response'"
(( chars <= 600 )) || die "Response too long ($chars chars), refusing to TTS"

echo "Ответ: $response"

# Audio output checks
out="$word.mp3"
[[ ! -e "$out" ]] || die "Output file already exists: $out"

# Generate audio
printf '%s' "$response" | ./tts.sh > "$out" || die "tts.sh failed"

# Verify file was created and non-empty
[[ -s "$out" ]] || die "Audio file not created or empty: $out"

echo "Озвучка сохранена в $out"
echo "=== Генерация любопытного факта и озвучки для рандомного слова - закончилась ==="

# Not implemented
echo "Error: Not Implemented"
exit 1

sd-create-picture.sh -n 4 -s 1024x1536 "Нарисуй мне картинку на тему: $word. Это должно быть что-то яркое, красочное, с элементами сюрреализма, в стиле цифрового искусства. Пусть это будет не просто иллюстрация слова, а нечто более абстрактное и вдохновляющее, что вызывает эмоции и любопытство. Не нужно букв или логотипов, только визуальная интерпретация слова в виде уникального произведения искусства."
