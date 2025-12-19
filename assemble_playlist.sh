#!/usr/bin/env bash
set -euo pipefail

# if [[ $# -ne 2 ]]; then
  # echo "Usage: $0 <playlist.xspf> <output.aac>"
  # exit 1
# fi
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <playlist.xspf>"
  exit 1
fi

playlist="$1"
output="${playlist%.*}.m4a"
outdir=".tmp"
fade=0.5
concat_file="$outdir/concat.txt"


if [[ ! -f "$playlist" ]]; then
  echo "Playlist not exists: $playlist"
  exit 1
fi

mkdir -p "$outdir"
rm -f "$concat_file"

mapfile -t tracks < <(
  xmlstarlet sel -N x="http://xspf.org/ns/0/"   -t -m "//x:track/x:location" -v . -n "$playlist"
)

echo "Обработка ${#tracks[@]} треков с затуханиями по ${fade}s..."

for url in "${tracks[@]}"; do
    # убираем file:/// в начале
    path="${url#file:///}"

    # декодируем %20 → пробелы
    path="${path//%20/ }"

    # имя файла
    file="${path##*/}"

    # infile="$(dirname "$playlist")/$file"
    infile="suno/$file"
    outfile="$outdir/${file%.*}.mp3"

    echo "file '$file'" >> "$concat_file"

    if [[ -f "$outfile" ]]; then
      echo "Skip (exists): $file"
      continue
    fi

    # длительность трека
    duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$infile")"
    fade_out_start=$(echo "$duration - $fade" | bc -l)

    ffmpeg -hide_banner -y -i "$infile" \
      -vn \
      -af "loudnorm,afade=t=in:ss=0:d=$fade,afade=t=out:st=$fade_out_start:d=$fade" \
      -b:a 192k \
      "$outfile"
done

ffmpeg -hide_banner -f concat -safe 0 -i "$concat_file" \
  -c:a aac -b:a 192k \
  "$output"
