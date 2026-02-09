#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# ---- tools ----
need ffmpeg
need ffprobe
need ls
need head
need wc
need mktemp

need ask-ai.sh
need tts.sh
need create-picture-2.sh

EXPLORER="/mnt/c/Windows/explorer.exe"

log_start() { echo "[$1] start -> $2" >&2; }
log_end()   { echo "[$1] end   -> $2" >&2; }

open_in_windows_explorer() {
  local file="$1"
  [[ -x "$EXPLORER" ]] || return 0
  if command -v wslpath >/dev/null 2>&1; then
    "$EXPLORER" "$(wslpath -w "$file")" >/dev/null 2>&1 || true
  else
    "$EXPLORER" "$file" >/dev/null 2>&1 || true
  fi
}

# ---- temp workspace ----
WORK_DIR="$(mktemp -d -t curiousfact.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
log_start "workdir" "$WORK_DIR"

# ---- generators ----
gen_word() {
  log_start "word" "random word"
  local w
  w="$(ask-ai.sh 'Придумай рандомное слово. Только одно слово, не слишком сложное и не слишком обычное.' \
    | tr -d '\r' | tr -s '[:space:]' ' ' | tr -d '[:space:]')"
  [[ -n "$w" ]] || die "Empty word"
  log_end "word" "$w"
  printf '%s' "$w"
}

gen_fact() {
  local w="$1"
  log_start "fact" "topic=$w"
  local r chars

  r="$(ask-ai.sh -s "$w" "$(cat <<'EOF'
Напиши текст для озвучки YouTube Shorts по теме из системного сообщения (одно слово).

Требования:
- Один реально любопытный факт, интересный сам по себе.
- 55–90 слов по-русски.
- Структура: крючок → объяснение → финальная фраза с вау-эффектом или вопросом.
- Без списков, заголовков, кавычек, эмодзи, ссылок, «в этом видео».
- Только чистый текст озвучки.
EOF
)" | tr -d '\r')"

  r="$(printf '%s' "$r" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$r" ]] || die "Empty response"

  chars="$(printf '%s' "$r" | wc -c | tr -d ' ')"
  log_end "fact" "ok, ${chars} chars"
  printf '%s' "$r"
}

gen_audio() {
  local text="$1" out="$2"
  log_start "audio" "$out"
  printf '%s' "$text" | tts.sh -v nova > "$out"
  [[ -s "$out" ]] || die "Audio not created"
  log_end "audio" "ok"
}

optimize_img_prompt() {
  local word="$1" fact="$2"
  log_start "imgprompt" "optimize"
  local p chars

  p="$(ask-ai.sh "$(cat <<EOF
Write ONE English text-to-image prompt for a portrait illustration (1024x1536) for YouTube Shorts.

Topic: "$word"
Narration text: "$fact"

Constraints:
- 20–60 words
- vivid colorful surreal digital art
- emotional, intriguing
- no text, letters, logos, watermarks
Return ONLY the prompt.
EOF
)")"

  p="$(printf '%s' "$p" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$p" ]] || die "Empty image prompt"

  chars="$(printf '%s' "$p" | wc -c | tr -d ' ')"
  log_end "imgprompt" "ok, ${chars} chars"
  printf '%s' "$p"
}

gen_images() {
  local prompt="$1" dir="$2"
  log_start "img" "generate"
  ( cd "$dir" && create-picture-2.sh -n 4 -s 1024x1536 "$prompt" >/dev/null )
  log_end "img" "generated"
}

make_video() {
  local audio="$1" dir="$2" video="$3"

  mapfile -t imgs < <(ls -t "$dir"/*.{png,jpg,jpeg} 2>/dev/null | head -n 20)
  (( ${#imgs[@]} >= 1 )) || die "No images found"

  local concat="$dir/concat.txt"
  : > "$concat"

  local abs
  for img in "${imgs[@]}"; do
    abs="$(realpath "$img")"
    echo "file '$abs'" >> "$concat"
    echo "duration 10" >> "$concat"
  done
  abs="$(realpath "${imgs[-1]}")"
  echo "file '$abs'" >> "$concat"

  log_start "video" "$video"
  ffmpeg -hide_banner -loglevel error -y \
    -f concat -safe 0 -i "$concat" \
    -i "$audio" \
    -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30" \
    -c:v libx264 -pix_fmt yuv420p \
    -c:a aac \
    -shortest \
    "$video"

  [[ -s "$video" ]] || die "Video not created"
  log_end "video" "ok"
}

# ---- pipeline ----
echo "=== Генерация факта + видео ==="

word="$(gen_word | tr '[:upper:]' '[:lower:]')"
printf '%s' "$word" > "$WORK_DIR/word.txt"

fact="$(gen_fact "$word")"
printf '%s' "$fact" > "$WORK_DIR/fact.txt"

audio="$WORK_DIR/$word.mp3"
gen_audio "$fact" "$audio"

img_prompt="$(optimize_img_prompt "$word" "$fact")"
printf '%s' "$img_prompt" > "$WORK_DIR/image_prompt.txt"
gen_images "$img_prompt" "$WORK_DIR"

video="$word.mp4"
make_video "$audio" "$WORK_DIR" "$video"

info="$word.txt"

meta="$(ask-ai.sh "$(cat <<EOF
Сгенерируй метаданные для YouTube Shorts по теме и тексту.
Тема: $word
Текст озвучки: $fact

Верни СТРОГО в таком формате (2 строки):
TITLE: ...
DESC: ...
EOF
)")"

header="$(printf '%s\n' "$meta" | sed -n 's/^TITLE:[[:space:]]*//p')"
content="$(printf '%s\n' "$meta" | sed -n 's/^DESC:[[:space:]]*//p')"

{
  printf 'Тема:\n%s\n\n' "$word"
  printf 'Факт:\n%s\n\n' "$fact"
  printf 'Промпт для картинки:\n%s\n\n' "$img_prompt"
  printf 'Заголовок: %s\n\n' "$header"
  printf 'Описание:\n%s\n\n' "$content"
} > "$info"

echo "OUTPUT_VIDEO=$video"
open_in_windows_explorer "$video"

echo "=== Готово ==="
