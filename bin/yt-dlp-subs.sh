# yt-dlp \
#     --all-subs \
#     --write-auto-subs \
#     --skip-download \
#     "$@"

yt-dlp \
    --windows-filenames \
    --sub-langs ru \
    --write-subs \
    --write-auto-subs \
    --skip-download \
    "$@"

yt-dlp \
    --windows-filenames \
    --sub-langs en \
    --write-subs \
    --write-auto-subs \
    --skip-download \
    "$@"
