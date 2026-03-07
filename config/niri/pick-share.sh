#!/usr/bin/env bash

choice=$(printf "Monitor\nWindow\nClear\nFake-Full" | fuzzel --dmenu)

case "$choice" in
    "Window")
        niri msg action set-dynamic-cast-window --id "$(niri msg --json pick-window | jq .id)"
        ;;
	"Fake-Full")
	niri msg action toggle-windowed-fullscreen --id $(niri msg --json pick-window | jq .id)
	;;
    "Monitor")
        niri msg action set-dynamic-cast-monitor
        ;;
    "Clear")
        niri msg action clear-dynamic-cast-target
        ;;
    *)
        exit 0
        ;;
esac

