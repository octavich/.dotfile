#!/usr/bin/env bash

DOWNLOAD_DIR="${HOME}/Videos/ytdlp"

URL=$(printf '' | fuzzel --dmenu \
    --prompt="url: " \
    --lines=0 \
    --width=60)

[[ -z "$URL" ]] && exit 0

mkdir -p "$DOWNLOAD_DIR"
notify-send "yt-dlp" "⬇ " --icon="~/.config/fuzzel/raw.png"

yt-dlp \
    --output "$DOWNLOAD_DIR/%(title)s.%(ext)s" \
    --merge-output-format mp4 \
    "$URL" && \
    notify-send "yt-dlp" "✓ $DOWNLOAD_DIR" --icon="~/.config/fuzzel/raw.png" || \
    notify-send "yt-dlp" " ✗ " --icon="~/.config/fuzzel/raw.png"
