#!/usr/bin/env bash
set -euo pipefail

. .env

# =========================
# 1) VARIABLES
# =========================
EXPLORER="/mnt/c/Windows/explorer.exe"
YOUTUBE_UPLOAD="${YOUTUBE_UPLOAD:-0}" # 1 to upload

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="${PROMPTS_DIR:-$SCRIPT_DIR/prompts}"

WORK_DIR=""

# =========================
# 2) FUNCTIONS
# =========================
die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

pfile() { printf '%s/%s' "$PROMPTS_DIR" "$1"; }
need_prompt() { [[ -s "$(pfile "$1")" ]] || die "Prompt missing/empty: $(pfile "$1")"; }
prompt() { need_prompt "$1"; cat "$(pfile "$1")"; }

trim() { printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

log() { echo "[$1] ${2:-}" >&2; }

timed_start() { echo "[$1] start -> ${2:-}" >&2; __T0="$SECONDS"; }
timed_end() {
  local tag="$1" msg="${2:-}"
  local elapsed
  elapsed="$(awk "BEGIN{printf \"%.1f\", ($SECONDS - ${__T0:-$SECONDS})}")"
  echo "[$tag] end   -> $msg (${elapsed}s)" >&2
}

open_in_windows_explorer() {
  local file="$1"
  [[ -x "$EXPLORER" ]] || return 0
  if command -v wslpath >/dev/null 2>&1; then
    "$EXPLORER" "$(wslpath -w "$file")" >/dev/null 2>&1 || true
  else
    "$EXPLORER" "$file" >/dev/null 2>&1 || true
  fi
}

sed_esc() { printf '%s' "$1" | tr -d '\r' | sed 's/[\/&|\\]/\\&/g'; }

render_topic_narration_file() {
  # $1 template_file, $2 topic (string), $3 narration_file (file path)
  # {{NARRATION}} must be on its own line in template
  local tpl="$1" topic_esc
  topic_esc="$(sed_esc "$2")"

  sed -e "s|{{TOPIC}}|$topic_esc|g" "$(pfile "$tpl")" | sed -e "/{{NARRATION}}/{
    r $3
    d
  }"
}

render_content_file() {
  # $1 template_file, $2 content_file
  # {{CONTENT}} must be on its own line in template
  sed -e "/{{CONTENT}}/{
    r $2
    d
  }" "$(pfile "$1")"
}

make_workdir() {
  WORK_DIR="$(mktemp -d -t curiousfact.XXXXXX)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  log workdir "$WORK_DIR"
}

gen_word() {
  timed_start gen_word "random word"
  local w
  w="$(ask-ai.sh "$(prompt create_random_word.txt)" | tr -d '\r' | tr -s '[:space:]' ' ' | tr -d '[:space:]')"
  [[ -n "$w" ]] || die "Empty word"
  timed_end gen_word "$w"
  printf '%s' "$w"
}

gen_fact() {
  local topic="$1"
  timed_start gen_fact "topic=$topic"

  local r
  r="$(ask-ai.sh -s "$topic" "$(prompt create_text_for_video.txt)" | tr -d '\r')"
  r="$(trim "$r")"
  [[ -n "$r" ]] || die "Empty fact"

  timed_end gen_fact "$(printf '%s' "$r" | wc -c | tr -d ' ') chars"
  printf '%s' "$r"
}

gen_audio() {
  local text="$1" out="$2"
  timed_start gen_audio "$out"
  printf '%s' "$text" | tts.sh -v nova > "$out"
  [[ -s "$out" ]] || die "Audio not created: $out"
  timed_end gen_audio "ok"
}

gen_img_prompt() {
  local topic="$1" fact_file="$2"
  timed_start optimize_img_prompt "topic=$topic"

  local p
  p="$(render_topic_narration_file create_image_prompt.txt "$topic" "$fact_file")"
  p="$(ask-ai.sh "$p")"
  p="$(trim "$p")"
  [[ -n "$p" ]] || die "Empty image prompt"

  timed_end optimize_img_prompt "$(printf '%s' "$p" | wc -c | tr -d ' ') chars"
  printf '%s' "$p"
}

gen_images() {
  local img_prompt="$1" dir="$2"
  timed_start gen_images "generate"
  ( cd "$dir" && create-picture-2.sh -n 4 -s 1024x1536 "$img_prompt" >/dev/null )
  timed_end gen_images "generated"
}

gen_meta() {
  local topic="$1" fact_file="$2"
  timed_start gen_meta "title/desc"

  local q
  q="$(render_topic_narration_file create_yt_meta.txt "$topic" "$fact_file")"
  ask-ai.sh "$q" | tr -d '\r'

  timed_end gen_meta "ok"
}

make_video() {
  local audio="$1" dir="$2" video="$3"

  mapfile -t imgs < <(ls -t "$dir"/*.{png,jpg,jpeg} 2>/dev/null | head -n 20)
  (( ${#imgs[@]} >= 1 )) || die "No images found"

  local concat="$dir/concat.txt"
  : > "$concat"

  local img abs
  for img in "${imgs[@]}"; do
    abs="$(realpath "$img")"
    printf "file '%s'\n" "$abs" >> "$concat"
    printf "duration 10\n" >> "$concat"
  done
  abs="$(realpath "${imgs[-1]}")"
  printf "file '%s'\n" "$abs" >> "$concat"

  timed_start make_video "$video"
  ffmpeg -hide_banner -loglevel error -y \
    -f concat -safe 0 -i "$concat" \
    -i "$audio" \
    -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30" \
    -c:v libx264 -pix_fmt yuv420p \
    -c:a aac \
    -shortest \
    "$video"

  [[ -s "$video" ]] || die "Video not created: $video"
  timed_end make_video "ok"
}

validate_info_with_ai() {
  local info_file="$1" q report verdict
  timed_start validate_info_with_ai "$info_file"

  [[ -s "$info_file" ]] || die "Info file missing/empty: $info_file"
  q="$(render_content_file validate.txt "$info_file")"

  report="$(ask-ai.sh "$q" | tr -d '\r')"
  report="$(trim "$report")"

  verdict="$(printf '%s\n' "$report" | sed -n 's/^VERDICT:[[:space:]]*//p' | head -n 1)"
  verdict="$(trim "$verdict")"

  if [[ "$verdict" != "PASS" ]]; then
    timed_end validate_info_with_ai "FAIL"
    printf '%s\n' "$report" >&2
    return 1
  fi

  timed_end validate_info_with_ai "PASS"
  return 0
}

do_upload() {
  local video="$1" title="$2" desc="$3"
  [[ "$YOUTUBE_UPLOAD" == "1" ]] || return 0

  [[ -s "$video" ]] || die "Video not found for upload: $video"
  [[ -n "${title// }" ]] || die "Empty title for upload"

  timed_start do_upload "$video"
  yt-up.sh -t "$title" -d "$desc" -p "private" "$(realpath "$video")"
  timed_end do_upload "ok"
}

cleanup_bg() {
  local pid
  for pid in "${pids[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}

# =========================
# 3) CHECKS
# =========================
need ffmpeg; need ffprobe; need awk; need sed; need tr; need wc; need mktemp; need realpath; need ls; need head
need ask-ai.sh; need tts.sh; need create-picture-2.sh
[[ "$YOUTUBE_UPLOAD" == "1" ]] && need yt-up.sh || true

need_prompt "create_random_word.txt"
need_prompt "create_text_for_video.txt"
need_prompt "create_image_prompt.txt"
need_prompt "create_yt_meta.txt"
need_prompt "validate.txt"

# =========================
# 4) PIPELINE
# =========================
echo "=== Fact + video generation ==="
timed_start total "pipeline"

make_workdir

word="$(gen_word | tr '[:upper:]' '[:lower:]')"
printf '%s' "$word" > "$WORK_DIR/word.txt"

fact="$(gen_fact "$word")"
printf '%s' "$fact" > "$WORK_DIR/fact.txt"

audio="$WORK_DIR/$word.mp3"

pids=()
trap 'cleanup_bg' ERR INT TERM

(
  gen_audio "$fact" "$audio"
) & pids+=("$!")

(
  img_prompt="$(gen_img_prompt "$word" "$WORK_DIR/fact.txt")"
  printf '%s' "$img_prompt" > "$WORK_DIR/image_prompt.txt"
  gen_images "$img_prompt" "$WORK_DIR"
) & pids+=("$!")

(
  gen_meta "$word" "$WORK_DIR/fact.txt" > "$WORK_DIR/meta_raw.txt"
) & pid_meta=$!

wait "${pids[0]}" || die "Audio task failed"
wait "${pids[1]}" || die "Images task failed"

img_prompt="$(cat "$WORK_DIR/image_prompt.txt")"
video="$word.mp4"
make_video "$audio" "$WORK_DIR" "$video"

wait "$pid_meta" || die "Meta task failed"
meta="$(cat "$WORK_DIR/meta_raw.txt")"

title="$(printf '%s\n' "$meta" | sed -n 's/^TITLE:[[:space:]]*//p' | head -n 1)"
desc="$(printf '%s\n' "$meta" | sed -n 's/^DESC:[[:space:]]*//p' | head -n 1)"
title="$(trim "$title")"
desc="$(trim "$desc")"

info="$word.txt"
{
  printf 'Topic:\n%s\n\n' "$word"
  printf 'Fact:\n%s\n\n' "$fact"
  printf 'Image prompt:\n%s\n\n' "$img_prompt"
  printf 'Title: %s\n\n' "$title"
  printf 'Description:\n%s\n\n' "$desc"
} > "$info"

validate_info_with_ai "$info" || die "Validation failed"
do_upload "$video" "$title" "$desc"

echo "OUTPUT_VIDEO=$video"
open_in_windows_explorer "$video"

timed_end total "done"
echo "=== Done ==="

## TODO
# Always add own tag
# Third account API key
