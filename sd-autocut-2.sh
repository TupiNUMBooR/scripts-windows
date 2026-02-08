#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# shellcheck disable=SC1091
. .env

usage() {
  echo "Usage: $0 images_dir mp3_dir amv_dir"
}

require_tools() {
  local missing=0
  for t in ffmpeg ffprobe shuf; do
    if ! command -v "$t" >/dev/null 2>&1; then
      echo "Missing required tool: $t"
      missing=1
    fi
  done
  (( missing == 0 )) || exit 1
}

require_env() {
  : "${SD_TMP_DIR:?SD_TMP_DIR is not set}"
}

init_paths() {
  images_dir="$1"
  mp3_dir="$2"
  outdir="$3"

  dt="$(date +%m%d)"
  concat_file="$outdir/concat.txt"
  fadedir="$SD_TMP_DIR/faded"
  full_audio="$SD_TMP_DIR/$outdir-full-audio.mp3"
  amv="$outdir.mp4"
}

ensure_dirs() {
  mkdir -p "$outdir" "$fadedir"
}

dir_has_files() {
  local dir="$1"
  local pattern="$2"
  compgen -G "$dir/$pattern" > /dev/null
}

pick_random_file() {
  local dir="$1"
  local pattern="$2"
  local picked
  picked="$(compgen -G "$dir/$pattern" | shuf -n 1 || true)"
  [[ -n "${picked:-}" ]] && echo "$picked"
}

select_mp3s_min_duration() {
  local dir="$1"
  local target_seconds="$2"

  local mp3s total_seconds
  total_seconds=0

  mapfile -t mp3s < <(compgen -G "$dir/*.mp3" | shuf)

  selected=()
  for f in "${mp3s[@]}"; do
    local dur secs
    dur="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 -- "$f" || true)"
    [[ -n "${dur:-}" ]] || continue

    secs="$(awk -v d="$dur" 'BEGIN{printf("%d\n", (d<0)?0:int(d+0.5))}')"
    (( secs > 0 )) || continue

    selected+=( "$f" )
    total_seconds=$((total_seconds + secs))

    if (( total_seconds >= target_seconds )); then
      break
    fi
  done

  if (( total_seconds < target_seconds )); then
    echo "Not enough playable mp3 duration in $dir (need >= ${target_seconds}s, got ${total_seconds}s)"
    exit 1
  fi

  echo "Selected mp3 count: ${#selected[@]}"
  echo "Selected mp3 total seconds: $total_seconds"
}

move_one_jpeg_if_needed() {
  if dir_has_files "$outdir" "*.jpeg"; then
    echo "Output directory already contains jpeg file: $outdir"
    return
  fi

  echo "Selecting a jpeg image from: $images_dir"
  local img
  img="$(pick_random_file "$images_dir" "*.jpeg")"
  if [[ -z "${img:-}" ]]; then
    echo "No images found in: $images_dir"
    exit 1
  fi

  mv -- "$img" "$outdir/"
  echo "Moved image to output directory: $img"
}

move_mp3s_if_needed() {
  if dir_has_files "$outdir" "*.mp3"; then
    echo "Output directory already contains mp3 files: $outdir"
    return
  fi

  echo "Selecting mp3 files from: $mp3_dir"
  if ! dir_has_files "$mp3_dir" "*.mp3"; then
    echo "No mp3 files found in: $mp3_dir"
    exit 1
  fi

  local target_seconds=1200
  select_mp3s_min_duration "$mp3_dir" "$target_seconds"

  for f in "${selected[@]}"; do
    mv -- "$f" "$outdir/"
  done
}

fade_mp3s() {
  local count
  count="$(compgen -G "$outdir/*.mp3" | wc -l | tr -d ' ')"
  echo "Processing $count tracks with fade ${fade}s..."

  for f in "$outdir"/*.mp3; do
    local base out duration fade_out_start
    base="$(basename "$f")"
    out="$fadedir/$base"

    if [[ -f "$out" ]]; then
      echo "Skip (exists): $out"
      continue
    fi

    duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$f")"
    fade_out_start="$(awk -v d="$duration" -v fi="$fade" 'BEGIN{printf("%.6f\n", d - fi)}')"

    ffmpeg -hide_banner -y \
      -i "$f" \
      -vn -b:a 192k \
      -af "loudnorm,afade=t=in:ss=0:d=$fade,afade=t=out:st=$fade_out_start:d=$fade" \
      "$out"
  done
}

write_concat_txt() {
  : > "$concat_file"

  mapfile -t shuffled < <(compgen -G "$outdir/*.mp3" | shuf)
  if (( ${#shuffled[@]} == 0 )); then
    echo "No mp3 files found in: $outdir"
    exit 1
  fi

  for _ in 1 2 3; do
    for f in "${shuffled[@]}"; do
      local base fn
      base="$(basename "$f")"
      fn="$fadedir/$base"
      printf "file '%s'\n" "$fn" >> "$concat_file"
    done
  done

  echo "Wrote: $concat_file"
}

build_full_audio() {
  ffmpeg -hide_banner -y \
    -f concat -safe 0 -i "$concat_file" \
    -c:a mp3 -b:a 192k \
    "$full_audio"
  echo "Created full audio file: $full_audio"
}

build_amv() {
  local cover
  cover="$(pick_random_file "$outdir" "*.jpeg")"
  if [[ -z "${cover:-}" ]]; then
    echo "No jpeg found in: $outdir"
    exit 1
  fi

  ffmpeg -hide_banner -y \
    -i "$cover" -i "$full_audio" \
    -map 0:v -map 1:a \
    -c:v libx264 -preset slow -crf 15 \
    -c:a copy \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -movflags +faststart \
    -pix_fmt yuv420p \
    "$amv"
  echo "Created AMV: $amv"
}

main() {
  if [[ $# -ne 3 ]]; then
    usage
    exit 1
  fi

  require_tools
  require_env
  init_paths "$1" "$2" "$3"
  ensure_dirs

  move_one_jpeg_if_needed
  move_mp3s_if_needed

  write_concat_txt
  fade_mp3s
  build_full_audio
  build_amv
}

images_dir=""
mp3_dir=""
dt=""
outdir=""
concat_file=""
fadedir=""
full_audio=""
amv=""
fade=0.5
selected=()

main "$@"
