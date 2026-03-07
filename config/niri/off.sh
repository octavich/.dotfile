#!/bin/bash

CONFIG_FILE="/home/whyoolw/.config/niri/config.kdl"
TMP_FILE="${CONFIG_FILE}.tmp"

# Считываем текущий статус eDP-1
EDP_BLOCK=$(awk '/output "eDP-1"[[:space:]]*\{/,/\}/' "$CONFIG_FILE")

if echo "$EDP_BLOCK" | grep -q 'off'; then
    # Включаем монитор: удаляем строку с "off"
    awk '
        BEGIN {inside=0}
        /output "eDP-1"[[:space:]]*\{/ {inside=1}
        inside && /off/ {next}
        inside && /\}/ {inside=0}
        {print}
    ' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
    echo "Монитор eDP-1 включен."
else
    # Выключаем монитор: добавляем "off" после строки с открывающей скобкой
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
    echo "Монитор eDP-1 выключен."
fi

