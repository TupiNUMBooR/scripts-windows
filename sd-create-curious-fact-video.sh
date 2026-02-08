#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# Tools always needed (even in -t for building video)
need ffmpeg
need ffprobe
need ls
need head
need wc

EXPLORER="/mnt/c/Windows/explorer.exe"
CACHE_DIR="${CACHE_DIR:-./tmp}"

usage() {
  cat >&2 <<'EOF'
Usage: sd-create-curious-fact-video.sh [-t]
  -t  test mode: reuse cached assets, SKIP all AI calls (word/fact/tts/images)
EOF
  exit 1
}

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

# ---- args ----
test_mode=0
while getopts ":th" opt; do
  case "$opt" in
    t) test_mode=1 ;;
    h) usage ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done

mkdir -p "$CACHE_DIR"

# Wipe cache ONLY at start, ONLY if not -t
if [[ "$test_mode" -eq 0 ]]; then
  # AI tools needed only in non-test mode
  need ask-ai.sh
  need ask-fact.sh
  need tts.sh
  need create-picture.sh

  log_start "cache" "wipe $CACHE_DIR"
  rm -rf "$CACHE_DIR"/*
  log_end "cache" "done"
else
  log_start "cache" "test mode, keep $CACHE_DIR (skip all AI calls)"
  log_end "cache" "done"
fi

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
  log_start "fact" "ask-fact.sh \"$w\""
  local r chars
  r="$(ask-fact.sh "$w" | tr -d '\r')"
  [[ -n "$r" ]] || die "Empty response"
  chars="$(printf '%s' "$r" | wc -c | tr -d ' ')"
  log_end "fact" "ok, ${chars} chars"
  printf '%s' "$r"
}

gen_audio() {
  local text="$1" out="$2"
  log_start "audio" "$out"
  printf '%s' "$text" | tts.sh > "$out"
  [[ -s "$out" ]] || die "Audio not created"
  log_end "audio" "ok"
}

optimize_img_prompt() {
  local word="$1" fact="$2"
  log_start "imgprompt" "ask-ai.sh"
  local p chars
  p="$(ask-ai.sh "$(cat <<EOF
Write ONE English text-to-image prompt for a portrait illustration (1024x1536) for YouTube Shorts based on:
Topic: "$word"
Fact: "$fact"
Constraints: 20-60 words, vivid colorful surreal digital art, emotional and intriguing, no text/letters/logos/watermarks. Return ONLY the prompt.
EOF
)")"
  p="$(printf '%s' "$p" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$p" ]] || die "Empty optimized prompt"
  chars="$(printf '%s' "$p" | wc -c | tr -d ' ')"
  log_end "imgprompt" "ok, ${chars} chars"
  printf '%s' "$p"
}

gen_images() {
  local prompt="$1" dir="$2"
  log_start "img" "generate 4 images, 1024x1536, dir=$dir"
  ( cd "$dir" && create-picture.sh -n 4 -s 1024x1536 "$prompt" >/dev/null )
  log_end "img" "generated"
}

pick_cached_word() {
  # Prefer saved word.txt, else derive from newest mp3, else "test"
  if [[ -s "$CACHE_DIR/word.txt" ]]; then
    cat "$CACHE_DIR/word.txt"
    return 0
  fi
  local mp3
  mp3="$(ls -t "$CACHE_DIR"/*.mp3 2>/dev/null | head -n 1 || true)"
  if [[ -n "${mp3:-}" ]]; then
    basename "$mp3" .mp3
    return 0
  fi
  printf '%s' "test"
}

log_images_used() {
  local -a imgs=("$@")
  log_start "img" "using ${#imgs[@]} image(s)"
  local i
  for i in "${!imgs[@]}"; do
    echo "[img] file[$((i+1))] -> ${imgs[$i]}" >&2
  done
  log_end "img" "listed"
}

make_video() {
  local audio="$1" dir="$2" video="$3"

  # Use whatever images exist (>=1). In non-test mode it will usually be 4.
  mapfile -t imgs < <(ls -t "$dir"/*.{png,jpg,jpeg} 2>/dev/null | head -n 20)
  (( ${#imgs[@]} >= 1 )) || die "No images found in $dir"

  # Fix the './tmp/./tmp/...' issue: concat paths are relative to concat file location.
  # Use ABSOLUTE paths in concat list.
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

  log_images_used "${imgs[@]}"

  log_start "video" "$video (1080x1920, 10s/img, cut to audio)"
  ffmpeg -y \
    -f concat -safe 0 -i "$concat" \
    -i "$audio" \
    -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30" \
    -c:v libx264 -pix_fmt yuv420p \
    -c:a aac \
    -shortest \
    "$video" >/dev/null

  [[ -s "$video" ]] || die "Video not created"
  local v_dur
  v_dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video" | tr -d '\r')"
  log_end "video" "ok, duration=${v_dur}s"
}

echo "=== Генерация факта + видео ==="

if [[ "$test_mode" -eq 1 ]]; then
  # ---- TEST MODE: no AI calls at all ----
  word="$(pick_cached_word)"
  log_end "word" "reuse -> $word"

  audio="$CACHE_DIR/$word.mp3"
  [[ -s "$audio" ]] || {
    # If word-derived audio not found, pick newest mp3
    audio="$(ls -t "$CACHE_DIR"/*.mp3 2>/dev/null | head -n 1 || true)"
    [[ -n "${audio:-}" && -s "$audio" ]] || die "No cached audio (*.mp3) found in $CACHE_DIR"
    word="$(basename "$audio" .mp3)"
    log_end "word" "derived -> $word"
  }
  log_end "audio" "reuse -> $audio"

  video="$word.mp4"
  make_video "$audio" "$CACHE_DIR" "$video"

  echo "OUTPUT_VIDEO=$video"
  open_in_windows_explorer "$video"
  exit 0
fi

# ---- NORMAL MODE: generate everything ----
word="$(gen_word)"
printf '%s' "$word" > "$CACHE_DIR/word.txt"

response="$(gen_fact "$word")"
printf '%s' "$response" > "$CACHE_DIR/response.txt"
echo "response=$(printf '%s' "$response")"

audio="$CACHE_DIR/$word.mp3"
gen_audio "$response" "$audio"

img_prompt="$(optimize_img_prompt "$word" "$response")"
printf '%s' "$img_prompt" > "$CACHE_DIR/image_prompt.txt"
gen_images "$img_prompt" "$CACHE_DIR"

video="$word.mp4"
make_video "$audio" "$CACHE_DIR" "$video"

echo "OUTPUT_VIDEO=$video"
open_in_windows_explorer "$video"

echo "=== Готово ==="
