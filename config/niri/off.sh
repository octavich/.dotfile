#!/bin/bash

CONFIG_FILE="~/.config/niri/config.kdl"
TMP_FILE="${CONFIG_FILE}.tmp"

EDP_BLOCK=$(awk '/output "eDP-1"[[:space:]]*\{/,/\}/' "$CONFIG_FILE")

if echo "$EDP_BLOCK" | grep -q 'off'; then
    awk '
        BEGIN {inside=0}
        /output "eDP-1"[[:space:]]*\{/ {inside=1}
        inside && /off/ {next}
        inside && /\}/ {inside=0}
        {print}
    ' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
else
    awk '
        BEGIN {inside=0}
        /output "eDP-1"[[:space:]]*\{/ {
            print
            print "    off"
            inside=1
            next
        }
        inside && /\}/ {inside=0}
        {print}
    ' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
fi

