#!/bin/bash

# Скрипт установки окружения (Niri + Waybar + Fish и системные утилиты)
set -e

echo "==> Обновление системы..."
sudo pacman -Syu --noconfirm

echo "==> Установка необходимых базовых пакетов..."
sudo pacman -S --needed --noconfirm base-devel git curl wget jq

# Установка AUR helper (paru), если его нет
if ! command -v paru &> /dev/null; then
    echo "==> Установка paru (AUR helper)..."
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    cd /tmp/paru
    makepkg -si --noconfirm
    rm -rf /tmp/paru
    cd -
else
    echo "==> paru уже установлен."
fi

echo "==> Установка системных утилит и пакетов..."
# Разделение пакетов по категориям для удобства
CORE=(
    niri
    waybar
    fish
    starship
    polkit-gnome
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
)
UI=(
    swww
    matugen
    nwg-look
    swaync
    fuzzel
    xsettingsd
)
TERMINAL=(
    kitty
    ghostty
)
FONTS=(
    ttf-jetbrains-mono-nerd
    noto-fonts
    noto-fonts-emoji
)
TOOLS=(
    fastfetch
    btop
    pwvucontrol
    wl-clipboard
    brightnessctl
    playerctl
    xdg-user-dirs
)

PACKAGES=("${CORE[@]}" "${UI[@]}" "${TERMINAL[@]}" "${FONTS[@]}" "${TOOLS[@]}")

paru -S --needed --noconfirm "${PACKAGES[@]}"

echo "==> Настройка конфигурационных файлов..."
# Клонирование репозитория с конфигами, если запуск идет через curl
REPO_URL="https://github.com/octavich/.dotfile.git"
DOTFILES_DIR="$HOME/.dotfile"

if [ ! -d "$DOTFILES_DIR" ]; then
    echo "==> Клонирование $REPO_URL в $DOTFILES_DIR..."
    git clone "$REPO_URL" "$DOTFILES_DIR"
else
    echo "==> Репозиторий конфигов уже существует в $DOTFILES_DIR. Обновляем..."
    cd "$DOTFILES_DIR"
    git pull
    cd -
fi

echo "==> Создание символических ссылок для .config..."
mkdir -p "$HOME/.config"

# Линкуем все файлы и папки из $DOTFILES_DIR/config/ в ~/.config/
cd "$DOTFILES_DIR/config"
for item in *; do
    if [ -e "$item" ]; then
        # Удаляем существующий конфиг перед линковкой, чтобы не было конфликтов
        if [ -e "$HOME/.config/$item" ] && [ ! -L "$HOME/.config/$item" ]; then
            echo "Бэкап существующего ~/.config/$item в ~/.config/${item}.bak"
            mv "$HOME/.config/$item" "$HOME/.config/${item}.bak"
        fi
        
        if [ "$item" = "gtk-3.0" ]; then
            mkdir -p "$HOME/.config/gtk-3.0"
            for gtk_item in "$DOTFILES_DIR/config/gtk-3.0/"*; do
                gtk_file=$(basename "$gtk_item")
                if [ "$gtk_file" = "bookmarks.template" ]; then
                    sed "s|\$HOME|$HOME|g" "$gtk_item" > "$HOME/.config/gtk-3.0/bookmarks"
                    echo "Сгенерировано bookmarks -> ~/.config/gtk-3.0/bookmarks"
                else
                    ln -sf "$gtk_item" "$HOME/.config/gtk-3.0/$gtk_file"
                    echo "Линковка $gtk_file -> ~/.config/gtk-3.0/$gtk_file"
                fi
            done
        else
            ln -sf "$DOTFILES_DIR/config/$item" "$HOME/.config/$item"
            echo "Линковка $item -> ~/.config/$item"
        fi
    fi
done

echo "==> Первичная настройка (шрифты, папки, темы)..."
fc-cache -fv >/dev/null 2>&1 || true
xdg-user-dirs-update || true

echo "==> Настройка служб Systemd..."
systemctl --user enable swaync.service || true

echo "==> Настройка fish по умолчанию..."
if [ "$SHELL" != "$(which fish)" ]; then
    chsh -s "$(which fish)"
fi

echo "==> Готово! Перезагрузите систему или зайдите заново, чтобы применить изменения."