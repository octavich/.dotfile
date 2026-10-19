#!/usr/bin/env bash
#
# Post-install check for the niri desktop. Changes nothing.
# shellcheck disable=SC2088  # "~/..." strings are only printed

set -uo pipefail
shopt -s nullglob

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

passes=0
warnings=0
failures=0

pass() { printf '  ok    %s\n' "$*"; passes=$((passes + 1)); }
warn() { printf '  warn  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '  FAIL  %s\n' "$*"; failures=$((failures + 1)); }
section() { printf '\n%s\n' "$*"; }

has() { command -v "$1" >/dev/null 2>&1; }

check_commands() {
    section "Programs"
    local cmd
    for cmd in niri niri-session noctalia xwayland-satellite fuzzel kitty foot fish starship \
        fastfetch ranger nvim clipse jams matugen hyprpicker flameshot brightnessctl \
        playerctl wpctl wl-copy jq yt-dlp notify-send sensors nautilus; do
        if has "$cmd"; then pass "$cmd"; else fail "$cmd is missing"; fi
    done
    # Bound in niri/config.kdl; your own tools are not installed by install.sh.
    for cmd in thfn-gtk translator-gtk calc-gtk currency-gtk /usr/local/bin/ytdl-gtk claude-desktop; do
        if has "$cmd"; then pass "$cmd"; else warn "$cmd is missing (bound in niri)"; fi
    done
}

check_links() {
    section "Config symlinks"
    local src name dst
    for src in "$REPO_DIR"/.config/*; do
        name=${src##*/}
        [[ $name == archive ]] && continue
        dst=$HOME/.config/$name
        if [[ -L $dst && $(readlink "$dst") == "$src" ]]; then
            pass "~/.config/$name"
        elif [[ -e $dst ]]; then
            fail "~/.config/$name exists but is not linked to the repo"
        else
            fail "~/.config/$name is missing"
        fi
    done
    if has niri; then
        if niri validate -c "$HOME/.config/niri/config.kdl" >/dev/null 2>&1; then
            pass "niri config is valid"
        else
            fail "niri validate reports errors: niri validate -c ~/.config/niri/config.kdl"
        fi
    fi
}

check_looks() {
    section "Fonts, icons, cursor"
    local family
    for family in "Liberation Mono" "Monocraft" "Symbols Nerd Font"; do
        if fc-list : family 2>/dev/null | grep -qi "$family"; then pass "font: $family"; else fail "font missing: $family"; fi
    done

    local theme dir found
    theme=$(sed -n 's/^[[:space:]]*xcursor-theme[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_DIR/.config/niri/config.kdl" | head -n 1)
    for theme in Neuwaita "$theme"; do
        found=""
        for dir in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
            [[ -d $dir/$theme ]] && found=$dir/$theme
        done
        if [[ -n $found ]]; then pass "theme: $found"; else warn "theme $theme is not installed"; fi
    done

    local plugin
    for plugin in ranger_devicons ranger-archives; do
        if [[ -d $HOME/.config/ranger/plugins/$plugin ]]; then pass "ranger plugin: $plugin"; else fail "ranger plugin missing: $plugin"; fi
    done
    if [[ -n $(ls -A "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/plugged" 2>/dev/null) ]]; then
        pass "nvim plugins"
    else
        fail "nvim plugins are not installed (:PlugInstall)"
    fi
}

check_session() {
    section "Session"
    local shell
    shell=$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)
    if [[ $shell == */fish ]]; then pass "login shell: $shell"; else warn "login shell is $shell, niri starts from fish on tty1"; fi

    if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
        warn "not inside a Wayland session; skipping runtime checks"
        return
    fi
    local env service
    env=$(systemctl --user show-environment 2>/dev/null)
    for service in XDG_CURRENT_DESKTOP=niri WAYLAND_DISPLAY; do
        if grep -q "^$service" <<<"$env"; then pass "systemd user env: $service"; else fail "systemd user env lacks $service"; fi
    done
    for service in pipewire.service pipewire-pulse.service wireplumber.service; do
        if systemctl --user is-active --quiet "$service"; then pass "$service"; else fail "$service is not running"; fi
    done
    for service in xdg-desktop-portal.service xdg-desktop-portal-gnome.service; do
        if systemctl --user is-failed --quiet "$service"; then
            fail "$service has failed"
        else
            pass "$service not failed"
        fi
    done
    if pgrep -x noctalia >/dev/null; then pass "noctalia is running"; else fail "noctalia is not running"; fi
}

check_nvidia() {
    local vendor found=0
    for vendor in /sys/bus/pci/devices/*/vendor; do
        [[ $(<"$vendor") == 0x10de ]] && found=1
    done
    [[ $found == 1 ]] || return 0
    section "NVIDIA"
    local module
    for module in nvidia nvidia_modeset nvidia_drm; do
        if [[ -d /sys/module/$module ]]; then pass "module $module"; else fail "module $module is not loaded"; fi
    done
    if [[ $(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null) == Y ]]; then
        pass "nvidia_drm modeset=Y"
    else
        fail "nvidia_drm modeset is off"
    fi
}

check_commands
check_links
check_looks
check_session
check_nvidia

printf '\nok: %d, warnings: %d, failures: %d\n' "$passes" "$warnings" "$failures"
[[ $failures -eq 0 ]]
