#!/usr/bin/env bash

if [[ -z "$1" ]]; then
  exit 1
fi

WALLPAPER="$1"

if [[ ! -f "$WALLPAPER" ]]; then
  exit 1
fi

SCHEMES=(
  "default"              
  "scheme-content"
  "scheme-expressive"
  "scheme-fidelity"
  "scheme-fruit-salad"
  "scheme-monochrome"
  "scheme-neutral"
  "scheme-rainbow"
  "scheme-tonal-spot"
)

ANSI_COLORS=""
for i in {0..8}; do
  ANSI_COLORS+="\e[48;5;${i}m  \e[0m"
done

for i in "${!SCHEMES[@]}"; do
  printf "%d) %-18s %b\n" $((i+1)) "${SCHEMES[$i]}" "$ANSI_COLORS"
done
echo

while true; do
  printf "#? "
  read -r choice
  tput cuu1 && tput el

  [[ "$choice" == "q" ]] && exit 0

  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#SCHEMES[@]} )); then
    SCHEME="${SCHEMES[$((choice-1))]}"
    
    if [[ "$SCHEME" == "default" ]]; then
      matugen image "$WALLPAPER" >/dev/null 2>&1
    else
      matugen image "$WALLPAPER" --type "$SCHEME" >/dev/null 2>&1
    fi
  fi
done
