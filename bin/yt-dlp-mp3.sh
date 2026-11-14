yt-dlp \
    -f "ba" \
    -x \
    --audio-format mp3 \
    --windows-filenames \
    --embed-thumbnail \
    --embed-metadata \
    --embed-chapters \
    "$@"
