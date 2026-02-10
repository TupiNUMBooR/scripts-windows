#!/usr/bin/env bash
set -euo pipefail

. .env

EXPLORER="/mnt/c/Windows/explorer.exe"

# Upload settings
YOUTUBE_UPLOAD="${YOUTUBE_UPLOAD:-0}"     # 1 to upload

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# ---- tools ----
need ffmpeg
need ffprobe
need ls
need head
need wc
need mktemp
need sed
need tr
need realpath
need python3
need awk

need ask-ai.sh
need tts.sh
need create-picture-2.sh

# ---- timing ----
declare -A __TIMER_START

log_start() {
  local tag="$1"
  local msg="${2:-}"
  __TIMER_START["$tag"]="$SECONDS"
  echo "[$tag] start -> $msg" >&2
}

log_end() {
  local tag="$1"
  local msg="${2:-}"
  local start="${__TIMER_START[$tag]:-}"

  if [[ -n "$start" ]]; then
    local elapsed
    elapsed=$(awk "BEGIN {printf \"%.1f\", ($SECONDS - $start)}")
    echo "[$tag] end   -> $msg (${elapsed}s)" >&2
    unset "__TIMER_START[$tag]"
  else
    echo "[$tag] end   -> $msg" >&2
  fi
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

trim() {
  # Trims leading/trailing whitespace and removes CR
  printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

create_temp() {
  # ---- temp workspace ----
  WORK_DIR="$(mktemp -d -t curiousfact.XXXXXX)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  log_start "workdir" "$WORK_DIR"
}

# ---- generators ----
gen_word() {
  log_start "word" "random word"
  local w
  w="$(ask-ai.sh 'Generate a random word. One word only, not too complex and not too common.' \
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
Write narration text for a YouTube Shorts video based on the topic from the system message (one word).

Style:
- Kurzgesagt-like: punchy, clean, playful science tone.
- Short sentences. Strong rhythm. Vivid but precise imagery.
- Light irony is OK. No cringe.

Hard constraints:
- 55–90 words in English.
- Structure: hook → explanation → final line with a punchy “wow” statement (NOT a question).
- Strictly NO viewer addressing: no "you", "your", "did you know", "imagine", "let’s", "watch", "look".
- No lists, headings, quotes, emojis, links, or “in this video”.
- Output only the clean narration text.
EOF
)" | tr -d '\r')"

  r="$(trim "$r")"
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
Write ONE English text-to-image prompt for a vertical illustration (1024x1536) for YouTube Shorts.

Topic: "$word"
Narration text: "$fact"

Style:
- Kurzgesagt-inspired infographic look: clean vector shapes, bold geometry, smooth gradients, high contrast, playful scientific vibe.
- Minimalist background, iconic central subject, tiny symbolic details.

Constraints:
- 25–60 words
- no text, letters, logos, watermarks
Return ONLY the prompt.
EOF
)")"

  p="$(trim "$p")"
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

gen_meta() {
  local word="$1" fact="$2"

  log_start "meta" "generate title/desc"
  ask-ai.sh "$(cat <<EOF
Generate metadata for a YouTube Shorts video based on the topic and narration text.
Make it match a Kurzgesagt-like tone: crisp, intriguing, science-y, slightly playful.

Constraints:
- English.
- TITLE: max 70 characters, no ALL CAPS.
- DESC: 1–2 short sentences + 3–6 hashtags at the end.
- No addressing the viewer ("you/your").
- No quotes.

Return STRICTLY in this format (2 lines):
TITLE: ...
DESC: ...
EOF
)" | tr -d '\r'
  log_end "meta" "ok"
}

validate_info_with_ai() {
  local info_file="$1"
  log_start "validate" "$info_file"

  [[ -s "$info_file" ]] || die "Info file not found or empty: $info_file"

  local report verdict chars
  report="$(ask-ai.sh "$(cat <<EOF
Check whether the content below follows the task constraints.

Rules to verify:
- Narration (Fact) is 55–90 English words.
- Kurzgesagt-like tone: punchy, clean, playful science.
- No viewer addressing: no "you", "your", "did you know", "imagine", "let's", "watch", "look".
- No lists, headings, quotes, emojis, links, or “in this video”.
- Image prompt: 25–60 words, Kurzgesagt-inspired infographic look, no text/logos/watermarks.
- Metadata: English. TITLE <= 70 chars, no ALL CAPS. DESC: 1–2 sentences + 3–6 hashtags. No "you/your". No quotes.

Return EXACTLY 2 lines:
VERDICT: PASS or FAIL
NOTES: short reason, mention which field breaks rules if any
CONTENT:
$(cat "$info_file")
EOF
)" | tr -d '\r')"

  report="$(trim "$report")"
  chars="$(printf '%s' "$report" | wc -c | tr -d ' ')"
  verdict="$(printf '%s\n' "$report" | sed -n 's/^VERDICT:[[:space:]]*//p' | head -n 1)"
  verdict="$(trim "$verdict")"

  if [[ "$verdict" != "PASS" ]]; then
    log_end "validate" "FAIL (${chars} chars)"
    printf '%s\n' "$report" >&2
    return 1
  fi

  log_end "validate" "PASS (${chars} chars)"
  return 0
}

do_upload() {
  local video="$1" title="$2" desc="$3"
  local videoreal="$(realpath "$video")"

  [[ "$YOUTUBE_UPLOAD" == "1" ]] || return 0

  [[ -s "$video" ]] || die "Video not found for upload: $video"
  [[ -n "${title// }" ]] || die "Empty title for upload"

  log_start "upload" "$video"
  yt-up.sh -t "$title" -d "$desc" -p "private" "$videoreal"
  log_end "upload" "ok"
}

# ---- pipeline ----
echo "=== Fact + video generation ==="
log_start "total" "pipeline"
create_temp

word="$(gen_word | tr '[:upper:]' '[:lower:]')"
printf '%s' "$word" > "$WORK_DIR/word.txt"

fact="$(gen_fact "$word")"
printf '%s' "$fact" > "$WORK_DIR/fact.txt"

audio="$WORK_DIR/$word.mp3"

# Track background PIDs to kill on failure
pids=()
cleanup_bg() {
  local pid
  for pid in "${pids[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}
trap 'cleanup_bg' ERR INT TERM

# Parallel stage: audio / images / meta
(
  gen_audio "$fact" "$audio"
) &
pid_audio=$!
pids+=("$pid_audio")

(
  img_prompt="$(optimize_img_prompt "$word" "$fact")"
  printf '%s' "$img_prompt" > "$WORK_DIR/image_prompt.txt"
  gen_images "$img_prompt" "$WORK_DIR"
) &
pid_img=$!
pids+=("$pid_img")

(
  meta="$(gen_meta "$word" "$fact")"
  printf '%s' "$meta" > "$WORK_DIR/meta_raw.txt"
) &
pid_meta=$!
pids+=("$pid_meta")

# Wait only what is needed for video first
wait "$pid_audio" || die "Audio task failed"
wait "$pid_img"   || die "Images task failed"

img_prompt="$(cat "$WORK_DIR/image_prompt.txt")"

video="$word.mp4"
make_video "$audio" "$WORK_DIR" "$video"

# Now wait for meta + validate; validation must kill everything and abort on failure
wait "$pid_meta"  || die "Meta task failed"
meta="$(cat "$WORK_DIR/meta_raw.txt")"

header="$(printf '%s\n' "$meta" | sed -n 's/^TITLE:[[:space:]]*//p' | head -n 1)"
content="$(printf '%s\n' "$meta" | sed -n 's/^DESC:[[:space:]]*//p' | head -n 1)"

header="$(trim "$header")"
content="$(trim "$content")"

info="$word.txt"
{
  printf 'Topic:\n%s\n\n' "$word"
  printf 'Fact:\n%s\n\n' "$fact"
  printf 'Image prompt:\n%s\n\n' "$img_prompt"
  printf 'Title: %s\n\n' "$header"
  printf 'Description:\n%s\n\n' "$content"
} > "$info"

validate_info_with_ai "$info" || die "Validation failed"

# Upload (optional) waits on video + meta + validation PASS (already satisfied here)
do_upload "$video" "$header" "$content"

echo "OUTPUT_VIDEO=$video"
open_in_windows_explorer "$video"

log_end "total" "done"
echo "=== Done ==="

## TODO
# Always add own tag
# Third account API key
