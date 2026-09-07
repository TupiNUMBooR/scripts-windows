#!/usr/bin/env bash
set -uo pipefail
# test-cv2.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CV2="$SCRIPT_DIR/../bin/cv2.sh"
WORK_DIR="$(mktemp -d /tmp/test-cv2.XXXXXX)"

passed=0
failed=0

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT INT TERM

pass() {
  printf '\n\033[1;32mPASS\033[0m %s\n' "$1"
  ((passed += 1))
}

fail() {
  printf '\n\033[1;31mFAIL\033[0m %s\n' "$1" >&2
  ((failed += 1))
}

section() {
  printf '\n\n\033[1;36m===== %s =====\033[0m\n' "$1"
}

run_test() {
  local name="$1"
  shift

  section "$name"
  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

expect_status() {
  local expected="$1"
  shift
  local actual

  "$@"
  actual=$?
  [[ "$actual" -eq "$expected" ]]
}

assert_file() {
  [[ -f "$1" && -s "$1" ]] || {
    printf 'Assertion failed: expected non-empty file: %s\n' "$1" >&2
    return 1
  }
}

assert_dir() {
  [[ -d "$1" ]]
}

assert_text() {
  local file="$1"
  local expected="$2"
  local actual

  [[ -f "$file" ]] || {
    printf 'Assertion failed: expected file: %s\n' "$file" >&2
    return 1
  }

  actual="$(cat -- "$file")"
  [[ "$actual" == "$expected" ]] || {
    printf 'Assertion failed: %s contains %q, expected %q\n' "$file" "$actual" "$expected" >&2
    return 1
  }
}

assert_audio_decodes() {
  ffmpeg -hide_banner -v error -i "$1" -map 0:a:0 -f null -
}

assert_video_decodes() {
  ffmpeg -hide_banner -v error -i "$1" -map 0:v:0 -frames:v 1 -f null -
}

probe_stream() {
  local file="$1"
  local selector="$2"
  local entry="$3"

  ffprobe -hide_banner -v error \
    -select_streams "$selector" \
    -show_entries "stream=$entry" \
    -of default=nw=1:nk=1 \
    "$file" | head -n 1
}

assert_stream_codec() {
  local file="$1"
  local selector="$2"
  local expected="$3"
  [[ "$(probe_stream "$file" "$selector" codec_name)" == "$expected" ]]
}

assert_pixel_format() {
  local file="$1"
  local expected="$2"
  [[ "$(probe_stream "$file" v:0 pix_fmt)" == "$expected" ]]
}

assert_video_height() {
  local file="$1"
  local expected="$2"
  [[ "$(probe_stream "$file" v:0 height)" == "$expected" ]]
}

image_size() {
  local source="$1"
  local frame="$WORK_DIR/frame-$RANDOM.png"
  ffmpeg -hide_banner -v error -y -i "$source" -map 0:v:0 -frames:v 1 "$frame"
  magick identify -format '%wx%h' "$frame"
  rm -f -- "$frame"
}

assert_image_format() {
  local file="$1"
  local expected="$2"
  local actual

  actual="$(magick identify -format '%m' "${file}[0]")" || return 1
  [[ "$actual" == "$expected" ]] || {
    printf 'Assertion failed: %s format is %s, expected %s\n' "$file" "$actual" "$expected" >&2
    return 1
  }
}

assert_image_size() {
  local file="$1"
  local expected="$2"
  local actual

  actual="$(magick identify -format '%wx%h' "${file}[0]")" || return 1
  [[ "$actual" == "$expected" ]] || {
    printf 'Assertion failed: %s size is %s, expected %s\n' "$file" "$actual" "$expected" >&2
    return 1
  }
}

make_fixtures() {
  section "Generate fixtures"

  mkdir -p \
    "$WORK_DIR/input/images/nested" \
    "$WORK_DIR/input/audio" \
    "$WORK_DIR/input/video" \
    "$WORK_DIR/input/files/nested"

  printf 'alpha\n' > "$WORK_DIR/input/files/a.txt"
  printf 'beta\n' > "$WORK_DIR/input/files/nested/b.txt"

  magick -size 64x48 gradient: "$WORK_DIR/input/images/a.png"
  magick -size 80x60 xc:skyblue "$WORK_DIR/input/images/nested/b.png"
  magick -size 32x24 xc:tomato "$WORK_DIR/input/images/nested/c.jpg"

  ffmpeg -hide_banner -y \
    -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' \
    -c:a pcm_s16le "$WORK_DIR/input/audio/tone.wav"

  ffmpeg -hide_banner -y \
    -f lavfi -i 'testsrc2=size=160x120:rate=4:duration=12' \
    -f lavfi -i 'sine=frequency=660:sample_rate=48000:duration=12' \
    -vf 'pad=320:240:80:60:black' \
    -c:v ffv1 -c:a pcm_s16le -shortest \
    "$WORK_DIR/input/video/sample.mkv"
}

check_cv2() {
  [[ -x "$CV2" ]] || {
    echo "Expected executable next to test: $CV2" >&2
    return 1
  }

  command -v ffprobe >/dev/null 2>&1 || {
    echo "Required test command not found: ffprobe" >&2
    return 127
  }
}

case_cp() {
  cd "$WORK_DIR"
  "$CV2" -vo output -s backup cp input/files/a.txt input/files/nested/b.txt
  assert_text output/input/files/a.backup.txt alpha &&
    assert_text output/input/files/nested/b.backup.txt beta
}

case_cp_overwrite() {
  cd "$WORK_DIR"
  printf 'old\n' > output/input/files/a.force.txt
  "$CV2" -y -o output -s force cp input/files/a.txt
  assert_text output/input/files/a.force.txt alpha
}

case_dry_run() {
  cd "$WORK_DIR"
  rm -f output/input/images/a.dry.jpg
  "$CV2" -nvo output -s dry jpg input/images/a.png
  [[ ! -e output/input/images/a.dry.jpg ]]
}

case_images() {
  cd "$WORK_DIR"
  "$CV2" -y -p 2 -o output -s converted -q 80 -r 50% jpg \
    input/images/a.png input/images/nested/b.png
  "$CV2" -y -o output -s converted png input/images/nested/c.jpg
  "$CV2" -y -o output -s converted -q 60 avif input/images/a.png

  assert_image_format output/input/images/a.converted.jpg JPEG &&
    assert_image_size output/input/images/a.converted.jpg 32x24 &&
    assert_image_format output/input/images/nested/b.converted.jpg JPEG &&
    assert_image_size output/input/images/nested/b.converted.jpg 40x30 &&
    assert_image_format output/input/images/nested/c.converted.png PNG &&
    assert_image_format output/input/images/a.converted.avif AVIF
}

case_audio() {
  cd "$WORK_DIR"
  # MP3 intentionally starts from a real video container. This verifies that
  # FFmpeg selects a usable audio stream without cv2 forcing -map or -vn.
  "$CV2" -y -p 2 -o output -s audio -q 4 mp3 input/video/sample.mkv
  "$CV2" -y -o output -s audio flac input/audio/tone.wav
  "$CV2" -y -o output -s audio -q 4 ogg input/audio/tone.wav
  "$CV2" -y -o output -s audio wav input/audio/tone.wav

  assert_file output/input/video/sample.audio.mp3 &&
    assert_audio_decodes output/input/video/sample.audio.mp3 &&
    assert_stream_codec output/input/video/sample.audio.mp3 a:0 mp3 &&
    assert_audio_decodes output/input/audio/tone.audio.flac &&
    assert_stream_codec output/input/audio/tone.audio.flac a:0 flac &&
    assert_audio_decodes output/input/audio/tone.audio.ogg &&
    assert_stream_codec output/input/audio/tone.audio.ogg a:0 vorbis &&
    assert_audio_decodes output/input/audio/tone.audio.wav &&
    assert_stream_codec output/input/audio/tone.audio.wav a:0 pcm_s16le
}

case_opus() {
  cd "$WORK_DIR"
  "$CV2" -y -o output -s audio opus input/audio/tone.wav
  assert_file output/input/audio/tone.audio.opus &&
    assert_audio_decodes output/input/audio/tone.audio.opus &&
    assert_stream_codec output/input/audio/tone.audio.opus a:0 opus
}

case_video_264() {
  cd "$WORK_DIR"
  "$CV2" -y -o output -s h264 -q 35 -r 480p 264 input/video/sample.mkv
  assert_file output/input/video/sample.h264.mp4 &&
    assert_video_decodes output/input/video/sample.h264.mp4 &&
    assert_audio_decodes output/input/video/sample.h264.mp4 &&
    assert_stream_codec output/input/video/sample.h264.mp4 v:0 h264 &&
    assert_stream_codec output/input/video/sample.h264.mp4 a:0 aac &&
    assert_pixel_format output/input/video/sample.h264.mp4 yuv420p &&
    assert_video_height output/input/video/sample.h264.mp4 480
}

case_video_265() {
  cd "$WORK_DIR"
  "$CV2" -y -o output -s h265 -q 40 265 input/video/sample.mkv
  assert_file output/input/video/sample.h265.mkv &&
    assert_video_decodes output/input/video/sample.h265.mkv &&
    assert_audio_decodes output/input/video/sample.h265.mkv &&
    assert_stream_codec output/input/video/sample.h265.mkv v:0 hevc &&
    assert_stream_codec output/input/video/sample.h265.mkv a:0 opus &&
    assert_pixel_format output/input/video/sample.h265.mkv yuv420p
}

case_video_10bit() {
  cd "$WORK_DIR"
  "$CV2" -y -o output -s ten -q 40 10bit input/video/sample.mkv
  assert_file output/input/video/sample.ten.mkv &&
    assert_video_decodes output/input/video/sample.ten.mkv &&
    assert_audio_decodes output/input/video/sample.ten.mkv &&
    assert_stream_codec output/input/video/sample.ten.mkv v:0 hevc &&
    assert_stream_codec output/input/video/sample.ten.mkv a:0 opus &&
    assert_pixel_format output/input/video/sample.ten.mkv yuv420p10le
}

case_vcrop() {
  cd "$WORK_DIR"
  "$CV2" -y -o output -s cropped -q 40 vcrop input/video/sample.mkv
  local original_size cropped_size
  original_size="$(image_size input/video/sample.mkv)"
  cropped_size="$(image_size output/input/video/sample.cropped.crop.mkv)"
  assert_file output/input/video/sample.cropped.crop.mkv &&
    assert_video_decodes output/input/video/sample.cropped.crop.mkv &&
    [[ "$cropped_size" != "$original_size" ]]
}

case_vstrip() {
  cd "$WORK_DIR"
  "$CV2" -y -o output -s clean vstrip input/video/sample.mkv
  assert_file output/input/video/sample.clean.strip.mkv &&
    assert_video_decodes output/input/video/sample.clean.strip.mkv &&
    assert_audio_decodes output/input/video/sample.clean.strip.mkv
}

case_gif() {
  cd "$WORK_DIR"
  "$CV2" -y -o output -s animated gif input/video/sample.mkv
  assert_image_format output/input/video/sample.animated.gif GIF
}

case_zip() {
  cd "$WORK_DIR"
  "$CV2" -y -o archives -s packed zip input/files/a.txt input/files/nested
  assert_file archives/input/files/a.txt.packed.zip &&
    assert_file archives/input/files/nested.packed.zip
}

case_zip_skip() {
  cd "$WORK_DIR"
  "$CV2" -y -o archives zip archives/input/files/a.txt.packed.zip
}

case_unzip() {
  cd "$WORK_DIR"
  "$CV2" -y -o extracted -s unpacked unzip archives/input/files/nested.packed.zip
  assert_text extracted/archives/input/files/nested.packed.unpacked/input/files/nested/b.txt beta
}

case_7z() {
  cd "$WORK_DIR"
  "$CV2" -y -o archives -s packed 7z input/files/a.txt input/files/nested/
  assert_file archives/input/files/a.txt.packed.7z &&
    assert_file archives/input/files/nested.packed.7z
}

case_7z_skip() {
  cd "$WORK_DIR"
  "$CV2" -y -o archives 7z archives/input/files/a.txt.packed.7z
}

case_un7z() {
  cd "$WORK_DIR"
  "$CV2" -y -o extracted -s unpacked un7z archives/input/files/nested.packed.7z
  assert_text extracted/archives/input/files/nested.packed.unpacked/input/files/nested/b.txt beta
}

case_7zp() {
  cd "$WORK_DIR"
  printf 'secret\nsecret\n' | "$CV2" -y -o archives -s secret 7zp input/files/a.txt
  assert_file archives/input/files/a.txt.secret.7z
  7z t -psecret archives/input/files/a.txt.secret.7z
}

case_validate() {
  "$CV2" validate
}

case_usage_errors() {
  cd "$WORK_DIR"
  expect_status 64 "$CV2" -q 5 gif input/video/sample.mkv &&
    expect_status 64 "$CV2" -r 720p mp3 input/audio/tone.wav &&
    expect_status 66 "$CV2" jpg input/images/missing.png
}

main() {
  check_cv2 || exit 1

  section "Validate full cv2 toolset"
  "$CV2" validate || exit $?

  make_fixtures || exit 1

  run_test "cp preserves directories and suffix" case_cp
  run_test "cp -y overwrites with -f" case_cp_overwrite
  run_test "dry-run creates nothing" case_dry_run
  run_test "jpg png avif and parallel images" case_images
  run_test "mp3 flac ogg wav" case_audio

  run_test "opus pipeline" case_opus

  run_test "H.264 MP4 conversion" case_video_264
  run_test "H.265 MKV conversion" case_video_265
  run_test "10-bit H.265 conversion" case_video_10bit
  run_test "crop detection and conversion" case_vcrop
  run_test "technical metadata stripping" case_vstrip
  run_test "palette GIF conversion" case_gif

  run_test "ZIP files and directories" case_zip
  run_test "ZIP input is skipped" case_zip_skip
  run_test "ZIP extraction" case_unzip

  run_test "7z files and trailing-slash directory" case_7z
  run_test "7z input is skipped" case_7z_skip
  run_test "7z extraction" case_un7z
  run_test "password-protected 7z" case_7zp
  run_test "validate all dependencies" case_validate

  run_test "usage and missing-input errors" case_usage_errors

  section "Result"
  printf 'Passed:  %d\n' "$passed"
  printf 'Failed:  %d\n' "$failed"
  printf 'Work dir cleaned on exit: %s\n' "$WORK_DIR"

  ((failed == 0))
}

main "$@"
