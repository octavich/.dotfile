#!/usr/bin/env bash

# Install Arch Linux dotfiles for niri, PipeWire, portals, GTK and fish.
set -Eeuo pipefail

REPO_URL="https://github.com/octavich/.dotfile.git"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfile}"
SWWW_REPO_URL="${SWWW_REPO_URL:-https://github.com/LGFae/swww.git}"
SWWW_VERSION="${SWWW_VERSION:-v0.11.2}"
INSTALL_OPTIONAL_AUR="${INSTALL_OPTIONAL_AUR:-0}"
NVIDIA_MODE="${NVIDIA_MODE:-auto}"
NVIDIA_DRIVER="${NVIDIA_DRIVER:-open}"
SESSION_MODE="${SESSION_MODE:-greetd}"
CHECK_ONLY="${CHECK_ONLY:-0}"
SUDO_KEEPALIVE_PID=""

installed_successfully=()
skipped_optional=()
failed_optional=()
failed_required=()
post_install_notes=()

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --with-optional-aur         Install optional AUR packages, including pwvucontrol.
  --nvidia                    Force NVIDIA package installation and modeset setup.
  --no-nvidia                 Skip NVIDIA package installation and modeset setup.
  --nvidia-driver=open        Use nvidia-open. This is the default for modern GPUs.
  --nvidia-driver=proprietary Use the proprietary nvidia package.
  --session=greetd            Configure greetd + tuigreet. This is the default.
  --session=tty               Keep tty1 fish autostart flow and disable greetd.
  --check                     Run preflight checks only; do not change the system.
  -h, --help                  Show this help.

Environment:
  INSTALL_OPTIONAL_AUR=1
  NVIDIA_MODE=auto|yes|no
  NVIDIA_DRIVER=open|proprietary
  SESSION_MODE=greetd|tty
  SWWW_REPO_URL=https://github.com/LGFae/swww.git
  SWWW_VERSION=v0.11.2
EOF
}

log_info() {
    printf '\n==> %s\n' "$*"
}

log_warn() {
    printf 'WARN: %s\n' "$*" >&2
}

log_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# shellcheck disable=SC2317
on_error() {
    local exit_code=$?
    log_error "Unexpected error on line ${BASH_LINENO[0]} (exit ${exit_code})."
    exit "$exit_code"
}

# shellcheck disable=SC2317
cleanup() {
    if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

trap on_error ERR
trap cleanup EXIT

for arg in "$@"; do
    case "$arg" in
        --with-optional-aur)
            INSTALL_OPTIONAL_AUR=1
            ;;
        --nvidia)
            NVIDIA_MODE="yes"
            ;;
        --no-nvidia)
            NVIDIA_MODE="no"
            ;;
        --nvidia-driver=open)
            NVIDIA_DRIVER="open"
            ;;
        --nvidia-driver=proprietary)
            NVIDIA_DRIVER="proprietary"
            ;;
        --session=greetd)
            SESSION_MODE="greetd"
            ;;
        --session=tty)
            SESSION_MODE="tty"
            ;;
        --check)
            CHECK_ONLY=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            usage
            exit 1
            ;;
    esac
done

if [ "$EUID" -eq 0 ]; then
    log_error "Do not run this script with sudo/root. It will ask for sudo when needed."
    exit 1
fi

if [ "$NVIDIA_MODE" != "auto" ] && [ "$NVIDIA_MODE" != "yes" ] && [ "$NVIDIA_MODE" != "no" ]; then
    log_error "NVIDIA_MODE must be auto, yes or no."
    exit 1
fi

if [ "$NVIDIA_DRIVER" != "open" ] && [ "$NVIDIA_DRIVER" != "proprietary" ]; then
    log_error "NVIDIA_DRIVER must be open or proprietary."
    exit 1
fi

if [ "$SESSION_MODE" != "greetd" ] && [ "$SESSION_MODE" != "tty" ]; then
    log_error "SESSION_MODE must be greetd or tty."
    exit 1
fi

preflight_checks() {
    log_info "Running preflight checks"

    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [ "${ID:-}" != "arch" ] && [[ " ${ID_LIKE:-} " != *" arch "* ]]; then
            log_error "This installer targets Arch Linux. Detected ID=${ID:-unknown}."
            failed_required+=("preflight:arch-linux")
        fi
    else
        log_error "/etc/os-release is missing."
        failed_required+=("preflight:os-release")
    fi

    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run this script with sudo/root."
        failed_required+=("preflight:not-root")
    fi

    if ! command_exists sudo; then
        log_error "sudo is required."
        failed_required+=("preflight:sudo")
    elif [ "$CHECK_ONLY" = "1" ] && ! sudo -n true >/dev/null 2>&1; then
        log_warn "sudo exists, but passwordless validation failed during --check. The real install may prompt for a password."
    fi

    if ! command_exists pacman; then
        log_error "pacman is required."
        failed_required+=("preflight:pacman")
    fi

    if ! command_exists systemctl || [ ! -d /run/systemd/system ]; then
        log_error "A systemd-booted Arch system is required."
        failed_required+=("preflight:systemd")
    fi

    if command_exists ping; then
        ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || log_warn "Network check failed: archlinux.org is unreachable."
    elif command_exists curl; then
        curl -fsI https://archlinux.org >/dev/null 2>&1 || log_warn "Network check failed: archlinux.org is unreachable."
    else
        log_warn "Neither ping nor curl is available for a network check."
    fi

    if ! command_exists git; then
        log_warn "git is not installed yet; pacman will install it."
    fi
}

start_sudo_keepalive() {
    sudo -v
    while true; do
        sudo -n true
        sleep 60
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

record_package_result() {
    local package_scope=$1
    local package_name=$2
    local status=$3

    case "$status" in
        success)
            installed_successfully+=("$package_scope:$package_name")
            ;;
        skipped_optional)
            skipped_optional+=("$package_scope:$package_name")
            ;;
        failed_optional)
            failed_optional+=("$package_scope:$package_name")
            ;;
        failed_required)
            failed_required+=("$package_scope:$package_name")
            ;;
    esac
}

pacman_package_exists() {
    pacman -Si "$1" >/dev/null 2>&1
}

install_pacman_packages() {
    local package_scope=$1
    shift

    local package_name
    for package_name in "$@"; do
        if ! pacman_package_exists "$package_name"; then
            if [ "$package_scope" = "required" ]; then
                log_error "Required pacman package is not available: $package_name"
                record_package_result "pacman" "$package_name" "failed_required"
            else
                log_warn "Optional pacman package is not available: $package_name"
                record_package_result "pacman" "$package_name" "failed_optional"
            fi
            continue
        fi

        log_info "Installing pacman package: $package_name"
        if sudo pacman -S --needed --noconfirm "$package_name"; then
            record_package_result "pacman" "$package_name" "success"
        elif [ "$package_scope" = "required" ]; then
            log_error "Failed to install required pacman package: $package_name"
            record_package_result "pacman" "$package_name" "failed_required"
        else
            log_warn "Failed to install optional pacman package: $package_name"
            record_package_result "pacman" "$package_name" "failed_optional"
        fi
    done
}

ensure_paru() {
    if command_exists paru; then
        return 0
    fi

    log_info "Installing paru AUR helper"
    local build_root
    build_root=$(mktemp -d)

    if ! git clone https://aur.archlinux.org/paru.git "$build_root/paru"; then
        rm -rf "$build_root"
        return 1
    fi

    if ! (cd "$build_root/paru" && makepkg -si --noconfirm); then
        rm -rf "$build_root"
        return 1
    fi

    rm -rf "$build_root"
}

install_aur_packages() {
    local package_scope=$1
    shift

    if [ "$#" -eq 0 ]; then
        return 0
    fi

    if ! ensure_paru; then
        log_error "paru is required for AUR packages but could not be installed."
        local package_name
        for package_name in "$@"; do
            if [ "$package_scope" = "required" ]; then
                record_package_result "aur" "$package_name" "failed_required"
            else
                record_package_result "aur" "$package_name" "failed_optional"
            fi
        done
        return 0
    fi

    local package_name
    for package_name in "$@"; do
        log_info "Installing AUR package: $package_name"
        if paru -S --needed --noconfirm "$package_name"; then
            record_package_result "aur" "$package_name" "success"
        elif [ "$package_scope" = "required" ]; then
            log_error "Failed to install required AUR package: $package_name"
            record_package_result "aur" "$package_name" "failed_required"
        else
            log_warn "Failed to install optional AUR package: $package_name"
            record_package_result "aur" "$package_name" "failed_optional"
        fi
    done
}

install_swww_from_github() {
    if [ -x /usr/local/bin/swww ] && [ -x /usr/local/bin/swww-daemon ]; then
        log_info "swww and swww-daemon are already installed in /usr/local/bin; skipping source build"
        installed_successfully+=("source:swww-present")
        return 0
    fi

    log_info "Installing swww from GitHub source: $SWWW_REPO_URL ($SWWW_VERSION)"

    local build_root
    build_root=$(mktemp -d)

    if ! git clone --depth 1 --branch "$SWWW_VERSION" "$SWWW_REPO_URL" "$build_root/swww"; then
        rm -rf "$build_root"
        failed_required+=("source:swww-clone")
        return 0
    fi

    if ! (cd "$build_root/swww" && cargo build --release); then
        rm -rf "$build_root"
        failed_required+=("source:swww-build")
        return 0
    fi

    sudo install -Dm755 "$build_root/swww/target/release/swww" /usr/local/bin/swww
    sudo install -Dm755 "$build_root/swww/target/release/swww-daemon" /usr/local/bin/swww-daemon

    if [ -f "$build_root/swww/completions/swww.fish" ]; then
        install -Dm644 "$build_root/swww/completions/swww.fish" "$HOME/.config/fish/completions/swww.fish"
    fi

    rm -rf "$build_root"
    installed_successfully+=("source:swww")
}

enable_user_services() {
    local services=("$@")

    if ! command_exists systemctl; then
        log_warn "systemctl not found; cannot enable user services now."
        post_install_notes+=("Run after login: systemctl --user enable --now ${services[*]}")
        return 0
    fi

    if ! systemctl --user show-environment >/dev/null 2>&1; then
        log_warn "systemd user session is not available; user services were not enabled now."
        post_install_notes+=("Run after first graphical login: systemctl --user enable --now ${services[*]}")
        return 0
    fi

    local service_name
    for service_name in "${services[@]}"; do
        log_info "Enabling user service: $service_name"
        if systemctl --user enable --now "$service_name"; then
            installed_successfully+=("systemd-user:$service_name")
        else
            log_warn "Failed to enable user service now: $service_name"
            failed_optional+=("systemd-user:$service_name")
            post_install_notes+=("Retry: systemctl --user enable --now $service_name")
        fi
    done
}

enable_multilib() {
    local pacman_conf="/etc/pacman.conf"
    local tmp_file

    log_info "Ensuring pacman multilib repository is enabled"

    if [ ! -f "$pacman_conf" ]; then
        failed_required+=("pacman:pacman.conf")
        return 0
    fi

    if awk '
        /^\[multilib\]/ { in_multilib = 1; found = 1; next }
        /^\[/ { in_multilib = 0 }
        in_multilib && /^Include[[:space:]]*=[[:space:]]*\/etc\/pacman\.d\/mirrorlist/ { include = 1 }
        END { exit !(found && include) }
    ' "$pacman_conf"; then
        log_info "multilib is already enabled"
        return 0
    fi

    tmp_file=$(mktemp)
    awk '
        BEGIN { in_multilib = 0; found = 0 }
        /^[[:space:]]*#\[multilib\]/ {
            print "[multilib]"
            in_multilib = 1
            found = 1
            next
        }
        /^\[multilib\]/ {
            print
            in_multilib = 1
            found = 1
            next
        }
        in_multilib && /^[[:space:]]*#Include[[:space:]]*=[[:space:]]*\/etc\/pacman\.d\/mirrorlist/ {
            print "Include = /etc/pacman.d/mirrorlist"
            in_multilib = 0
            next
        }
        /^\[/ { in_multilib = 0 }
        { print }
        END {
            if (found == 0) {
                print ""
                print "[multilib]"
                print "Include = /etc/pacman.d/mirrorlist"
            }
        }
    ' "$pacman_conf" > "$tmp_file"

    sudo install -m 0644 "$tmp_file" "$pacman_conf"
    rm -f "$tmp_file"

    if sudo pacman -Sy --noconfirm; then
        installed_successfully+=("pacman:multilib")
    else
        failed_required+=("pacman:multilib-sync")
    fi
}

configure_greetd_session() {
    log_info "Configuring greetd + tuigreet"

    if ! command_exists systemctl; then
        failed_required+=("session:systemctl")
        return 0
    fi

    local tmp_config
    tmp_config=$(mktemp)
    cat > "$tmp_config" <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --asterisks --remember --remember-session --sessions /usr/share/wayland-sessions --cmd niri-session"
user = "greeter"
EOF

    sudo install -d -m 0755 /etc/greetd
    sudo install -m 0644 "$tmp_config" /etc/greetd/config.toml
    rm -f "$tmp_config"
    installed_successfully+=("config:/etc/greetd/config.toml")

    if sudo systemctl enable greetd.service; then
        installed_successfully+=("systemd:greetd.service")
    else
        failed_required+=("systemd:greetd.service")
    fi

    if sudo systemctl set-default graphical.target; then
        installed_successfully+=("systemd:graphical.target")
    else
        failed_optional+=("systemd:graphical.target")
    fi

    post_install_notes+=("Reboot; greetd/tuigreet will offer niri-session as the default session.")
}

configure_tty_session() {
    log_info "Configuring tty session mode"

    if command_exists systemctl; then
        sudo systemctl disable greetd.service >/dev/null 2>&1 || true
        if sudo systemctl set-default multi-user.target; then
            installed_successfully+=("systemd:multi-user.target")
        else
            failed_optional+=("systemd:multi-user.target")
        fi
    fi

    post_install_notes+=("Log into tty1; fish will exec niri-session.")
}

configure_session_startup() {
    case "$SESSION_MODE" in
        greetd)
            configure_greetd_session
            ;;
        tty)
            configure_tty_session
            ;;
    esac
}

detect_nvidia_gpu() {
    if [ "$NVIDIA_MODE" = "yes" ]; then
        return 0
    fi

    if [ "$NVIDIA_MODE" = "no" ]; then
        return 1
    fi

    if command_exists lspci && lspci | grep -Ei 'nvidia|3d controller|vga' | grep -qi nvidia; then
        return 0
    fi

    if [ -d /sys/bus/pci/devices ] && grep -Rqi '^0x10de$' /sys/bus/pci/devices/*/vendor 2>/dev/null; then
        return 0
    fi

    return 1
}

rebuild_initramfs_if_available() {
    if command_exists mkinitcpio; then
        log_info "Rebuilding initramfs with mkinitcpio"
        if sudo mkinitcpio -P; then
            installed_successfully+=("nvidia:mkinitcpio")
        else
            failed_required+=("nvidia:mkinitcpio")
        fi
    else
        log_warn "mkinitcpio not found; rebuild initramfs manually if your kernel setup requires it."
        post_install_notes+=("If NVIDIA modules do not load after reboot, rebuild initramfs for your kernel.")
    fi
}

configure_nvidia_modeset() {
    if ! detect_nvidia_gpu; then
        log_info "NVIDIA GPU was not detected; skipping NVIDIA modeset setup."
        return 0
    fi

    log_info "Configuring NVIDIA DRM modeset"

    if [ -f /etc/default/grub ]; then
        if grep -q 'nvidia-drm.modeset=1' /etc/default/grub; then
            log_info "nvidia-drm.modeset=1 is already present in /etc/default/grub"
        else
            local current_value
            local new_value
            local tmp_file

            current_value=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | head -n 1 || true)
            current_value=${current_value#GRUB_CMDLINE_LINUX_DEFAULT=}
            current_value=${current_value#\"}
            current_value=${current_value%\"}
            current_value=${current_value#\'}
            current_value=${current_value%\'}
            new_value="${current_value} nvidia-drm.modeset=1"
            new_value=${new_value# }

            tmp_file=$(mktemp)

            awk -v new_line="GRUB_CMDLINE_LINUX_DEFAULT=\"$new_value\"" '
                BEGIN { updated = 0 }
                /^GRUB_CMDLINE_LINUX_DEFAULT=/ {
                    print new_line
                    updated = 1
                    next
                }
                { print }
                END {
                    if (updated == 0) {
                        print new_line
                    }
                }
            ' /etc/default/grub > "$tmp_file"

            sudo cp "$tmp_file" /etc/default/grub
            rm -f "$tmp_file"
            log_info "Added nvidia-drm.modeset=1 to /etc/default/grub"
        fi

        if command_exists grub-mkconfig; then
            if sudo grub-mkconfig -o /boot/grub/grub.cfg; then
                installed_successfully+=("nvidia:nvidia-drm.modeset=1")
            else
                failed_required+=("nvidia:grub-mkconfig")
            fi
        else
            log_warn "grub-mkconfig not found; regenerate GRUB config manually."
            post_install_notes+=("Regenerate GRUB config so nvidia-drm.modeset=1 reaches the kernel cmdline.")
        fi
    elif [ -d /boot/loader/entries ]; then
        log_warn "systemd-boot detected. This script does not edit loader entries automatically."
        post_install_notes+=("Add nvidia-drm.modeset=1 to your systemd-boot loader entry options line.")
    else
        log_warn "No GRUB config or systemd-boot entries detected."
        post_install_notes+=("Ensure your bootloader passes nvidia-drm.modeset=1 to the kernel.")
    fi

    rebuild_initramfs_if_available
}

link_path() {
    local source_path=$1
    local target_path=$2

    mkdir -p "$(dirname "$target_path")"
    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        rm -rf "$target_path"
    fi
    ln -sfn "$source_path" "$target_path"
    installed_successfully+=("symlink:$target_path")
}

remove_path_for_replace() {
    local target_path=$1

    if [ -z "$target_path" ] || [ "$target_path" = "/" ] || [ "$target_path" = "$HOME" ]; then
        log_error "Refusing to remove unsafe path: ${target_path:-<empty>}"
        return 1
    fi

    rm -rf "$target_path"
}

setup_gtk3_config() {
    local gtk_target="$HOME/.config/gtk-3.0"
    mkdir -p "$gtk_target"

    local source_path
    for source_path in "$DOTFILES_DIR/config/gtk-3.0/"*; do
        local file_name
        file_name=$(basename "$source_path")

        case "$file_name" in
            bookmarks.template)
                sed "s|\$HOME|$HOME|g" "$source_path" > "$gtk_target/bookmarks"
                installed_successfully+=("config:$gtk_target/bookmarks")
                ;;
            bookmarks)
                ;;
            *)
                link_path "$source_path" "$gtk_target/$file_name"
                ;;
        esac
    done
}

setup_symlinks() {
    log_info "Setting up dotfile symlinks"
    mkdir -p "$HOME/.config"

    local item_path
    for item_path in "$DOTFILES_DIR/config/"*; do
        local item_name
        item_name=$(basename "$item_path")

        if [ "$item_name" = "gtk-3.0" ]; then
            setup_gtk3_config
        else
            link_path "$item_path" "$HOME/.config/$item_name"
        fi
    done
}

add_session_packages() {
    if [ "$SESSION_MODE" != "greetd" ]; then
        return 0
    fi

    official_required_packages+=(greetd)

    if pacman_package_exists greetd-tuigreet; then
        official_required_packages+=(greetd-tuigreet)
    elif pacman_package_exists tuigreet; then
        official_required_packages+=(tuigreet)
    else
        aur_required_packages+=(greetd-tuigreet)
    fi
}

print_array() {
    local title=$1
    shift

    printf '\n%s\n' "$title"
    if [ "$#" -eq 0 ]; then
        printf '  none\n'
        return 0
    fi

    local item
    for item in "$@"; do
        printf '  - %s\n' "$item"
    done
}

print_summary() {
    printf '\n'
    printf '========== Install summary ==========\n'
    print_array "Installed successfully:" "${installed_successfully[@]}"
    print_array "Skipped optional:" "${skipped_optional[@]}"
    print_array "Failed optional:" "${failed_optional[@]}"
    print_array "Failed required:" "${failed_required[@]}"
    print_array "Post-install checklist:" "${post_install_notes[@]}"
    printf '\n'

    if [ "${#failed_optional[@]}" -gt 0 ]; then
        log_warn "Optional failures were detected; installation can still be usable."
    fi
}

official_required_packages=(
    base-devel
    git
    curl
    wget
    jq
    dbus
    pciutils
    rust
    pkgconf
    lz4
    wayland
    wayland-protocols
    fish
    niri
    kitty
    fastfetch
    pipewire
    pipewire-pulse
    wireplumber
    pavucontrol
    lib32-pipewire
    lib32-libpulse
    lib32-alsa-plugins
    lib32-vulkan-icd-loader
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    qt6-wayland
    gtk4
    libadwaita
    adwaita-icon-theme
    xorg-xwayland
    waybar
    starship
    polkit-gnome
    pipewire-alsa
    pipewire-jack
    matugen
    nwg-look
    swaync
    fuzzel
    xsettingsd
    adw-gtk-theme
    papirus-icon-theme
    ttf-jetbrains-mono-nerd
    noto-fonts
    noto-fonts-emoji
    loupe
    clapper
    nemo
    nemo-fileroller
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    gst-libav
    btop
    micro
    wl-clipboard
    brightnessctl
    playerctl
    xdg-user-dirs
    os-prober
)

official_optional_packages=(
    rofi
    hyprpicker
    flameshot
)

aur_required_packages=(
    vicinae-bin
    bibata-cursor-theme-bin
)

aur_optional_packages=(
    pwvucontrol
)

preflight_checks

if [ "$CHECK_ONLY" = "1" ]; then
    post_install_notes+=("Selected session mode: $SESSION_MODE")
    if detect_nvidia_gpu; then
        post_install_notes+=("NVIDIA detected; installer would install $NVIDIA_DRIVER driver path and configure nvidia-drm.modeset=1.")
    else
        post_install_notes+=("NVIDIA was not detected or was disabled with --no-nvidia.")
    fi
    print_summary
    if [ "${#failed_required[@]}" -gt 0 ]; then
        exit 1
    fi
    exit 0
fi

if [ "${#failed_required[@]}" -gt 0 ]; then
    print_summary
    exit 1
fi

if ! command_exists sudo; then
    log_error "sudo is required."
    exit 1
fi

if ! command_exists pacman; then
    log_error "pacman is required. This installer is intended for Arch Linux."
    exit 1
fi

if detect_nvidia_gpu; then
    if [ "$NVIDIA_DRIVER" = "open" ]; then
        official_required_packages+=(nvidia-open)
    else
        official_required_packages+=(nvidia)
    fi
    official_required_packages+=(nvidia-utils)
    official_required_packages+=(lib32-nvidia-utils)
    official_optional_packages+=(libva-nvidia-driver)
fi

log_info "Updating system"
start_sudo_keepalive
enable_multilib
if ! sudo pacman -Syu --noconfirm; then
    failed_required+=("pacman:system-upgrade")
fi

add_session_packages

if pacman_package_exists xwayland-satellite; then
    official_required_packages+=(xwayland-satellite)
else
    aur_required_packages+=(xwayland-satellite)
fi

install_pacman_packages "required" "${official_required_packages[@]}"
install_pacman_packages "optional" "${official_optional_packages[@]}"
install_aur_packages "required" "${aur_required_packages[@]}"
install_swww_from_github

if [ "$INSTALL_OPTIONAL_AUR" = "1" ]; then
    install_aur_packages "optional" "${aur_optional_packages[@]}"
else
    for package_name in "${aur_optional_packages[@]}"; do
        record_package_result "aur" "$package_name" "skipped_optional"
    done
fi

log_info "Preparing dotfiles repository"
if [ ! -d "$DOTFILES_DIR/.git" ]; then
    if [ -e "$DOTFILES_DIR" ]; then
        remove_path_for_replace "$DOTFILES_DIR"
    fi
    if ! git clone "$REPO_URL" "$DOTFILES_DIR"; then
        failed_required+=("git:clone-dotfiles")
    fi
elif ! git -C "$DOTFILES_DIR" pull --ff-only; then
    failed_required+=("git:update-dotfiles")
fi

if [ -d "$DOTFILES_DIR/config" ]; then
    setup_symlinks
else
    failed_required+=("config:dotfiles-config-directory")
fi

log_info "Running post-install setup"
fc-cache -fv >/dev/null 2>&1 || log_warn "fc-cache failed."
xdg-user-dirs-update || log_warn "xdg-user-dirs-update failed."

mkdir -p "$HOME/Pictures"
cp -n "$DOTFILES_DIR/wallpapers/"* "$HOME/Pictures/" 2>/dev/null || true

wallpaper_path="$HOME/Pictures/кристюшкинс.jpg"
if [ -f "$wallpaper_path" ]; then
    matugen image "$wallpaper_path" || log_warn "matugen failed."
    "$HOME/.config/apply-theme.sh" || log_warn "apply-theme.sh failed."
fi

gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' || log_warn "Failed to set GTK theme."
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' || log_warn "Failed to set icon theme."
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' || log_warn "Failed to set cursor theme."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || log_warn "Failed to set color scheme."

enable_user_services pipewire.service pipewire-pulse.service wireplumber.service
enable_user_services swaync.service vicinae.service
configure_session_startup
configure_nvidia_modeset

if command_exists fish && [ "${SHELL:-}" != "$(command -v fish)" ]; then
    if chsh -s "$(command -v fish)"; then
        installed_successfully+=("shell:fish")
    else
        failed_optional+=("shell:fish")
        post_install_notes+=("Set fish manually: chsh -s \"$(command -v fish)\"")
    fi
fi

if [ "$SESSION_MODE" = "greetd" ]; then
    post_install_notes+=("Reboot into greetd/tuigreet and select niri-session if it is not selected automatically.")
else
    post_install_notes+=("Log into tty1; fish will exec niri-session for the graphical session.")
fi
post_install_notes+=("Verify PipeWire: pactl info; systemctl --user status pipewire pipewire-pulse wireplumber")
post_install_notes+=("Verify portals: systemctl --user status xdg-desktop-portal xdg-desktop-portal-gtk")
post_install_notes+=("Verify XWayland: echo \$WAYLAND_DISPLAY; echo \$DISPLAY; ps aux | grep -Ei 'xwayland|xwayland-satellite'")

print_summary

if [ "${#failed_required[@]}" -gt 0 ]; then
    exit 1
fi

exit 0
