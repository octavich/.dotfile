#!/usr/bin/env bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 /path/to/wallpaper.jpg"
    exit 1
fi

WALLPAPER="$1"

if [[ ! -f "$WALLPAPER" ]]; then
    echo "Error: File $WALLPAPER not found."
    exit 1
fi

# 1. Change wallpaper with a nice transition
swww img "$WALLPAPER" --transition-type center --transition-step 150 --transition-fps 120

# 2. Generate and apply colors (it will update colors.conf, Waybar, Kitty, etc.)
matugen image "$WALLPAPER"

echo "Theme updated from $WALLPAPER!"
