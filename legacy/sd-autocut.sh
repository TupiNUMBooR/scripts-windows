#!/usr/bin/env bash
set -euo pipefail
. .env
shopt -s nullglob

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 images_dir mp3_dir"
  exit 1
fi

: "${SD_TMP_DIR:?SD_TMP_DIR is not set}"
images_dir=$1
mp3_dir=$2
dt="$(date +%m%d)"
outdir="./$dt"
concat_file="$outdir/concat.txt"
fadedir="$SD_TMP_DIR/faded"
full_audio="$SD_TMP_DIR/$dt-full-audio.mp3"
fade=0.5
amv="$outdir/amv.mp4"

mkdir -p "$outdir"
mkdir -p "$fadedir"

# moving image
if [[ ! -z $(echo "$outdir"/*.jpeg) ]]; then
  echo "Output directory already contains jpeg file: $outdir"
else
  echo "Selecting a jpeg image from: $images_dir"
  img="$(ls "$images_dir"/*.jpeg 2>/dev/null | shuf -n 1)"
  if [[ ! -f "$img" ]]; then
    echo "No images found in: $images_dir"
    exit 1
  fi

  mv "$img" "$outdir/"
  echo "Moved image to output directory: $img"
fi

# selecting mp3s
if [[ ! -z $(echo "$outdir"/*.mp3) ]]; then
  echo "Output directory already contains mp3 files: $outdir"
else
  echo "Selecting mp3 files from: $mp3_dir"

  mp3s=( "$mp3_dir"/*.mp3 )
  if (( ${#mp3s[@]} == 0 )); then
    echo "No mp3 files found in: $mp3_dir"
    exit 1
  fi

  target_seconds=$((20 * 60))
  total_seconds=0
  selected=()

  # Shuffle list
  mapfile -t shuffled < <(printf '%s\n' "${mp3s[@]}" | shuf)

  for f in "${shuffled[@]}"; do
    dur="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 -- "$f" || true)"
    if [[ -z "${dur:-}" ]]; then
      continue
    fi

    secs="$(awk -v d="$dur" 'BEGIN{printf("%d\n", (d<0)?0:int(d+0.5))}')"
    if (( secs <= 0 )); then
      continue
    fi

    selected+=( "$f" )
    total_seconds=$((total_seconds + secs))

    if (( total_seconds >= target_seconds )); then
      break
    fi
  done

  if (( total_seconds < target_seconds )); then
    echo "Not enough playable mp3 duration in $mp3_dir (need >= ${target_seconds}s, got ${total_seconds}s)"
    exit 1
  fi

  echo "Selected mp3 count: ${#selected[@]}"
  echo "Selected mp3 total seconds: $total_seconds"

  # Copy selected mp3s into output folder (keep basenames)
  for f in "${selected[@]}"; do
    mv "$f" "$outdir"
  done
fi


# Build concat.txt repeating the playlist 3 times (>60 min if base >=20 min)
: > "$concat_file"

mp3s=( "$outdir"/*.mp3 )
if (( ${#mp3s[@]} == 0 )); then
  echo "No mp3 files found in: $outdir"
  exit 1
fi

mapfile -t shuffled < <(printf '%s\n' "${mp3s[@]}" | shuf)

for _ in 1 2 3; do
  for f in "${shuffled[@]}"; do
    fbase="$(basename "$f")"
    fn="$fadedir/$fbase"
    printf "file '%s'\n" "$fn" >> "$concat_file"
  done
done

echo "Wrote: $concat_file"


# add fade to mp3s
echo "Processing ?? tracks with fade ${fade}s..."

for f in "$outdir"/*.mp3; do
  fbase="$(basename "$f")"
  fn="$fadedir/$fbase"

  if [[ -f "$fn" ]]; then
    echo "Skip (exists): $fn"
    continue
  fi

  # track duration
  duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")"
  fade_out_start=$(echo "$duration - $fade" | bc -l)

  ffmpeg -hide_banner -y \
    -i "$f" \
    -vn -b:a 192k \
    -af "loudnorm,afade=t=in:ss=0:d=$fade,afade=t=out:st=$fade_out_start:d=$fade" \
    "$fn"
done


ffmpeg -hide_banner -y \
  -f concat -safe 0 -i "$concat_file" \
  -c:a mp3 -b:a 192k \
  "$full_audio"
echo "Created full audio file: $full_audio"


ffmpeg -hide_banner -y \
  -i "$outdir"/*.jpeg -i "$full_audio" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset slow -crf 15 \
  -c:a copy \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -movflags +faststart \
  -pix_fmt yuv420p \
  "$amv"
echo "Created AMV: $amv"
