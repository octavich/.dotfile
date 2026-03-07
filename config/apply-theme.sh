#!/usr/bin/env bash

COLORS_CONF="$HOME/.config/colors.conf"
KITTY_COLORS="$HOME/.config/kitty/colors.conf"
WAYBAR_COLORS="$HOME/.config/waybar/colors.css"

if [[ ! -f "$COLORS_CONF" ]]; then
    echo "Error: $COLORS_CONF not found."
    exit 1
fi

# Update Kitty colors (it's the same format)
cp "$COLORS_CONF" "$KITTY_COLORS"

# Generate Waybar colors (CSS format)
echo "/* Generated from colors.conf */" > "$WAYBAR_COLORS"
while read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    key=$(echo "$line" | awk '{print $1}')
    val=$(echo "$line" | awk '{print $2}')
    echo "@define-color $key $val;" >> "$WAYBAR_COLORS"
done < "$COLORS_CONF"

# Reload Kitty
pkill -SIGUSR1 kitty

# Reload Waybar
pkill -SIGUSR2 waybar

echo "Theme applied!"
