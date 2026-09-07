# scripts-windows

A personal toolbox of small command-line utilities for Windows, WSL, media processing, AI APIs, and everyday developer tasks.

Most scripts are standalone and can be copied or added to your `PATH` individually. The runnable tools live in `bin/`; `wsl/` contains WSL configuration and package lists, while `legacy/` contains retired scripts.

## Highlights

| Tool | What it does |
| --- | --- |
| `cv2.sh` | Convert video, audio and images; create/extract archives; resize, crop, run jobs in parallel, and preserve directory structure. |
| `ask-ai-text.sh` | Send text to the OpenAI Responses API from a file, argument, or stdin; save responses and track cost. |
| `ask-ai-image.sh` | Generate images through the OpenAI image API and save them as PNG, WebP or JPEG. |
| `ask-ai-dialogue.sh` | Small CLI for multi-turn AI conversations. |
| `ask-tts.sh` | Generate speech through the OpenAI API. |
| `yt-dlp-mp3.sh` | Download YouTube audio and create an MP3 with the video thumbnail embedded as cover art. |
| `Update.ps1` | Bootstrap/update a Windows + WSL development environment. |
| `wsl-*.sh` | Small helpers for maintaining packages and updating WSL. |

There are also tiny helpers for Git, `winget`, PATH management, elevation, Trello, subtitles, passwords, and other repetitive jobs.

## Examples

```bash
cv2.sh 265 -q 26 -r 1080p video.mov
cv2.sh jpg -q 88 -r 50% -o converted images/*.png

printf '%s\n' 'Explain this code' | ask-ai-text.sh
yt-dlp-mp3.sh https://www.youtube.com/watch?v=dQw4w9WgXcQ
```

Each larger script has built-in help:

```bash
cv2.sh --help
ask-ai-text.sh --help
ask-ai-image.sh --help
```

## Requirements

Dependencies vary by script. Common ones include Bash/WSL, PowerShell, `ffmpeg`, ImageMagick, `yt-dlp`, `jq`, `curl`, `7z`, and an OpenAI API key for the AI tools.

Use `cv2.sh validate` to check its external dependencies.

## Notes

This repository is primarily my own working toolbox, so some scripts are intentionally opinionated or machine-specific. The `legacy/` directory contains older scripts and is not part of the current toolset.
