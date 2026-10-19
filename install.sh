#!/usr/bin/env bash
#
# Arch Linux + niri dotfiles installer.
#
#   packages/*.txt  package groups: official repos first, AUR as a fallback
#   .config/*       symlinked into ~/.config (whatever was there is backed up)
#
# ./install.sh --help for options.

set -Eeuo pipefail
shopt -s nullglob

REPO_URL="${REPO_URL:-https://github.com/octavich/.dotfile.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfile}"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/dotfile/backup"
STAMP="$(date +%Y%m%d-%H%M%S)"
NVIDIA_DRIVER="${NVIDIA_DRIVER:-nvidia-open-dkms}"
REMUS_URL="https://www.gnome-look.org/p/2355234"

# Kept in the repo, never linked into ~/.config.
LINK_EXCLUDE=(archive)

# Own programs referenced by niri/config.kdl that no package provides.
CUSTOM_APPS=(thfn-gtk translator-gtk calc-gtk currency-gtk /usr/local/bin/ytdl-gtk)

DRY_RUN=0
DO_PACKAGES=1
DO_CONFIGS=1
DO_UNLINK=0
SKIP_REVIEW="${SKIP_REVIEW:-0}"
GPU="${GPU:-auto}"
ONLY_GROUPS=""
SKIP_GROUPS=""

REPO_DIR=""
AUR_HELPER=""
SUDO_PID=""
GPU_VENDORS=""
MULTILIB_PENDING=0
declare -A REPO_SET=()

ok_list=()
warn_list=()
fail_list=()
note_list=()

if [[ -t 1 ]]; then
    C_BOLD=$'\e[1m' C_YELLOW=$'\e[33m' C_RED=$'\e[31m' C_RESET=$'\e[0m'
else
    C_BOLD="" C_YELLOW="" C_RED="" C_RESET=""
fi

step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
ok()   { ok_list+=("$*"); }
warn() { printf '%sWARN:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; warn_list+=("$*"); }
fail() { printf '%sFAIL:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; fail_list+=("$*"); }
note() { note_list+=("$*"); }
die()  { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# Run a command, or only print it with --dry-run.
run() {
    if [[ $DRY_RUN == 1 ]]; then
        printf '    [dry-run]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

# write_root_file <path> <content>
write_root_file() {
    if [[ $DRY_RUN == 1 ]]; then
        info "[dry-run] write $1"
        return 0
    fi
    sudo install -d -m 0755 "$(dirname "$1")"
    printf '%s\n' "$2" | sudo tee "$1" >/dev/null
}

on_error() {
    local status=$? i trace=""
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
        trace+=" ${FUNCNAME[i]}:${BASH_LINENO[i - 1]}"
    done
    die "unexpected error (exit $status) at$trace"
}

cleanup() {
    if [[ -n $SUDO_PID ]]; then
        kill "$SUDO_PID" 2>/dev/null || true
    fi
}

trap on_error ERR
trap cleanup EXIT

# ---------------------------------------------------------------- arguments

group_name() {
    local name=${1##*/}
    name=${name%.txt}
    printf '%s\n' "${name#[0-9]*-}"
}

# Groups from packages/*.txt plus the detected GPU drivers.
list_groups() {
    local file
    for file in "$REPO_DIR"/packages/*.txt; do
        group_name "$file"
    done
    printf '%s\n' gpu
}

usage() {
    local groups="(see packages/)"
    if [[ -n $REPO_DIR ]]; then
        groups=$(list_groups | paste -sd ' ')
    fi
    cat <<EOF
Usage: ./install.sh [options]

  -n, --dry-run        Show what would be done, change nothing.
      --only=G1,G2     Install only these package groups.
      --skip=G1,G2     Skip these package groups.
      --no-packages    Only link configs.
      --no-configs     Only install packages.
      --gpu=LIST       GPU drivers (group "gpu"): auto (default), none, or e.g. intel,nvidia.
  -y, --yes            Do not stop to review AUR PKGBUILDs.
      --unlink         Remove the config symlinks and restore backups.
  -h, --help           Show this help.

Package groups: $groups

Environment: DOTFILES_DIR (default ~/.dotfile), NVIDIA_DRIVER (default nvidia-open-dkms).
EOF
}

parse_args() {
    local arg
    for arg in "$@"; do
        case $arg in
            -n|--dry-run) DRY_RUN=1 ;;
            --only=*) ONLY_GROUPS=${arg#*=} ;;
            --skip=*) SKIP_GROUPS=${arg#*=} ;;
            --no-packages) DO_PACKAGES=0 ;;
            --no-configs) DO_CONFIGS=0 ;;
            --gpu=*) GPU=${arg#*=} ;;
            -y|--yes) SKIP_REVIEW=1 ;;
            --unlink) DO_UNLINK=1 ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; die "unknown option: $arg" ;;
        esac
    done
}

# ---------------------------------------------------------------- repo

# Sets REPO_DIR when the script runs from a checkout of the repo.
find_local_repo() {
    local self=${BASH_SOURCE[0]:-} dir
    if [[ -n $self && -f $self ]]; then
        dir=$(cd "$(dirname "$self")" && pwd -P)
        if [[ -d $dir/.config && -d $dir/packages ]]; then
            REPO_DIR=$dir
        fi
    fi
}

# Started through curl: fetch the repo, then re-run the installer from it.
bootstrap() {
    step "Fetching dotfiles into $DOTFILES_DIR"
    if ! command -v git >/dev/null; then
        sudo pacman -S --needed --noconfirm git
    fi
    if [[ -d $DOTFILES_DIR/.git ]]; then
        git -C "$DOTFILES_DIR" pull --ff-only || warn "could not update $DOTFILES_DIR, using it as is"
    elif [[ -e $DOTFILES_DIR ]]; then
        die "$DOTFILES_DIR exists but is not a git repo; move it away or set DOTFILES_DIR"
    else
        git clone "$REPO_URL" "$DOTFILES_DIR"
    fi
    # With `curl | bash` stdin is the script itself; hand the terminal back for prompts.
    if [[ ! -t 0 ]] && { : </dev/tty; } 2>/dev/null; then
        exec bash "$DOTFILES_DIR/install.sh" "$@" </dev/tty
    fi
    exec bash "$DOTFILES_DIR/install.sh" "$@"
}

# ---------------------------------------------------------------- system

preflight() {
    step "Preflight"
    local os
    # shellcheck disable=SC1091
    os=$(. /etc/os-release 2>/dev/null && printf '%s %s' "${ID:-}" "${ID_LIKE:-}") || true
    if [[ " $os " != *" arch "* ]]; then
        die "this installer is for Arch Linux (detected: ${os:-unknown})"
    fi
    local cmd
    for cmd in pacman sudo curl; do
        command -v "$cmd" >/dev/null || die "$cmd is required"
    done
    if [[ ! -d /run/systemd/system ]]; then
        warn "systemd is not running; services will not be enabled"
    fi
    if ! curl -fsI --max-time 10 https://archlinux.org >/dev/null 2>&1; then
        warn "archlinux.org is not reachable; check the network"
    fi
    info "repo: $REPO_DIR"
}

start_sudo() {
    if [[ $DRY_RUN == 1 ]]; then
        return 0
    fi
    sudo -v || die "sudo authentication failed"
    (while sleep 50; do sudo -n true 2>/dev/null || exit 0; done) &
    SUDO_PID=$!
}

enable_multilib() {
    local conf=/etc/pacman.conf
    if grep -q '^\[multilib\]' "$conf"; then
        return 0
    fi
    step "Enabling [multilib]"
    MULTILIB_PENDING=1
    run sudo cp "$conf" "$conf.dotfile.bak"
    if grep -q '^#\[multilib\]$' "$conf"; then
        run sudo sed -i '/^#\[multilib\]$/{s/^#//;n;s/^#Include/Include/}' "$conf"
    else
        run sudo sh -c "printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> $conf"
    fi
    ok "pacman: [multilib] enabled (backup: $conf.dotfile.bak)"
}

system_upgrade() {
    step "Updating the system"
    run sudo pacman -Sy --needed --noconfirm archlinux-keyring || die "pacman -Sy failed"
    run sudo pacman -Su --noconfirm || die "system upgrade failed; fix it and run the installer again"
    run sudo pacman -S --needed --noconfirm base-devel git || die "could not install base-devel and git"
    if [[ $DRY_RUN == 0 ]]; then
        MULTILIB_PENDING=0
    fi
}

ensure_aur_helper() {
    local helper
    for helper in paru yay; do
        if command -v "$helper" >/dev/null; then
            AUR_HELPER=$helper
            return 0
        fi
    done

    step "Installing paru (AUR helper)"
    if [[ $DRY_RUN == 1 ]]; then
        info "[dry-run] build paru-bin from the AUR"
        AUR_HELPER=paru
        return 0
    fi
    local pkg tmp
    for pkg in paru-bin paru; do
        if pacman -Q paru-bin >/dev/null 2>&1; then
            # paru-bin is installed but broken (e.g. libalpm bump): replace it.
            sudo pacman -Rdd --noconfirm paru-bin || true
        fi
        tmp=$(mktemp -d)
        if git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$tmp/$pkg" &&
            (cd "$tmp/$pkg" && makepkg -si --noconfirm) &&
            paru --version >/dev/null 2>&1; then
            rm -rf "$tmp"
            AUR_HELPER=paru
            ok "aur helper: $pkg"
            return 0
        fi
        rm -rf "$tmp"
        warn "could not install $pkg"
    done
    fail "no AUR helper available; AUR packages are skipped"
}

# ---------------------------------------------------------------- packages

group_selected() {
    local group=$1
    if [[ -n $ONLY_GROUPS && ",$ONLY_GROUPS," != *",$group,"* ]]; then
        return 1
    fi
    [[ ",$SKIP_GROUPS," != *",$group,"* ]]
}

check_group_names() {
    local known group
    known=",$(list_groups | paste -sd ','),"
    for group in ${ONLY_GROUPS//,/ } ${SKIP_GROUPS//,/ }; do
        if [[ $known != *",$group,"* ]]; then
            die "unknown package group: $group (available: ${known:1:-1})"
        fi
    done
}

# Package specs from a group file, any number per line. `a|b` means: the first
# one found in the official repos, otherwise the first one found in the AUR.
read_specs() {
    sed -e 's/#.*//' "$1" | tr -s ' \t' '\n' | sed '/^$/d'
}

has_vendor() {
    [[ ",$GPU_VENDORS," == *",$1,"* ]]
}

detect_gpu_vendors() {
    if [[ $GPU != auto ]]; then
        GPU_VENDORS=${GPU/none/}
        return 0
    fi
    local dev class vendor
    for dev in /sys/bus/pci/devices/*; do
        [[ -r $dev/class && -r $dev/vendor ]] || continue
        class=$(<"$dev/class")
        vendor=$(<"$dev/vendor")
        [[ $class == 0x03* ]] || continue
        case $vendor in
            0x8086) GPU_VENDORS+=",intel" ;;
            0x1002) GPU_VENDORS+=",amd" ;;
            0x10de) GPU_VENDORS+=",nvidia" ;;
        esac
    done
    GPU_VENDORS=${GPU_VENDORS#,}
}

gpu_specs() {
    if has_vendor intel; then
        printf '%s\n' mesa vulkan-intel lib32-vulkan-intel intel-media-driver
    fi
    if has_vendor amd; then
        printf '%s\n' mesa vulkan-radeon lib32-vulkan-radeon
    fi
    if has_vendor nvidia; then
        # Legacy branches (nvidia-580xx-dkms) need their matching utils.
        local branch=""
        if [[ $NVIDIA_DRIVER =~ ^nvidia-([0-9]+xx)- ]]; then
            branch=-${BASH_REMATCH[1]}
        fi
        printf '%s\n' "$NVIDIA_DRIVER" "nvidia$branch-utils" "lib32-nvidia$branch-utils" libva-nvidia-driver
        if [[ $NVIDIA_DRIVER == *-dkms ]]; then
            # DKMS needs headers for every installed kernel.
            local kernel
            while read -r kernel; do
                case $kernel in
                    *-headers|*-firmware*|*-docs) continue ;;
                esac
                if [[ -n ${REPO_SET[$kernel-headers]+x} ]]; then
                    printf '%s\n' "$kernel-headers"
                fi
            done < <(pacman -Qq 2>/dev/null | grep -E '^linux' || true)
        fi
    fi
}

load_repo_set() {
    local name
    REPO_SET=()
    while read -r name; do
        if [[ -n $name ]]; then
            REPO_SET[$name]=1
        fi
    done < <(pacman -Slq 2>/dev/null || true)
}

in_repos() {
    if [[ -n ${REPO_SET[$1]+x} ]]; then
        return 0
    fi
    # [multilib] is only enabled for real later in a dry run.
    [[ $MULTILIB_PENDING == 1 && $1 == lib32-* ]]
}

# Prints the names among "$@" that exist in the AUR (one RPC request).
aur_lookup() {
    local query="" name json
    for name in "$@"; do
        query+="&arg[]=$name"
    done
    json=$(curl -fsS --globoff --max-time 30 "https://aur.archlinux.org/rpc/v5/info?${query#&}") || return 1
    grep -o '"Name":"[^"]*"' <<<"$json" | cut -d'"' -f4 || true
}

pacman_install() {
    run sudo pacman -S --needed --noconfirm "$@"
}

aur_install() {
    local -a flags=(-S --needed --noconfirm)
    if [[ $AUR_HELPER == paru && $SKIP_REVIEW == 1 ]]; then
        flags+=(--skipreview)
    fi
    run "$AUR_HELPER" "${flags[@]}" "$@"
}

# install_with <installer function> <label> <packages...>
# One transaction first; if it fails, package by package to find the culprit.
install_with() {
    local installer=$1 label=$2 pkg
    shift 2
    if [[ $# -eq 0 ]]; then
        return 0
    fi
    if "$installer" "$@"; then
        for pkg in "$@"; do ok "$label: $pkg"; done
        return 0
    fi
    warn "$label: batch install failed, retrying one by one"
    for pkg in "$@"; do
        if "$installer" "$pkg"; then
            ok "$label: $pkg"
        else
            fail "$label: $pkg"
        fi
    done
}

install_packages() {
    step "Resolving packages"
    check_group_names
    load_repo_set
    detect_gpu_vendors
    info "GPU: ${GPU_VENDORS:-none}"

    local -a specs=()
    local file group
    for file in "$REPO_DIR"/packages/*.txt; do
        group=$(group_name "$file")
        if group_selected "$group"; then
            mapfile -t -O "${#specs[@]}" specs < <(read_specs "$file")
        else
            info "skipping group: $group"
        fi
    done
    if group_selected gpu; then
        mapfile -t -O "${#specs[@]}" specs < <(gpu_specs)
    fi

    local -a repo=() pending=() aur=() missing=() alts=()
    local -A seen=()
    local spec alt found
    for spec in "${specs[@]}"; do
        [[ -z ${seen[$spec]+x} ]] || continue
        seen[$spec]=1
        IFS='|' read -ra alts <<<"$spec"

        found=""
        for alt in "${alts[@]}"; do
            if pacman -T "$alt" >/dev/null 2>&1; then
                found=installed
                break
            fi
        done
        if [[ -n $found ]]; then
            ok "installed: $spec"
            continue
        fi

        for alt in "${alts[@]}"; do
            if in_repos "$alt"; then
                found=$alt
                break
            fi
        done
        if [[ -n $found ]]; then
            repo+=("$found")
        else
            pending+=("$spec")
        fi
    done

    if [[ ${#pending[@]} -gt 0 ]]; then
        local -A in_aur=()
        local -a candidates=()
        local name names
        for spec in "${pending[@]}"; do
            IFS='|' read -ra alts <<<"$spec"
            candidates+=("${alts[@]}")
        done
        if names=$(aur_lookup "${candidates[@]}"); then
            for name in $names; do in_aur[$name]=1; done
            for spec in "${pending[@]}"; do
                found=""
                IFS='|' read -ra alts <<<"$spec"
                for alt in "${alts[@]}"; do
                    if [[ -n ${in_aur[$alt]+x} ]]; then
                        found=$alt
                        break
                    fi
                done
                if [[ -n $found ]]; then
                    aur+=("$found")
                else
                    missing+=("$spec")
                fi
            done
        else
            warn "AUR is not reachable; trying the first name of each remaining package"
            for spec in "${pending[@]}"; do aur+=("${spec%%|*}"); done
        fi
    fi

    info "official repos (${#repo[@]}): ${repo[*]:-none}"
    info "AUR (${#aur[@]}): ${aur[*]:-none}"
    for spec in "${missing[@]}"; do
        fail "package not found in repos or AUR: $spec"
    done

    step "Installing packages from the official repos"
    install_with pacman_install repo "${repo[@]}"

    if [[ ${#aur[@]} -gt 0 ]]; then
        step "Installing packages from the AUR"
        if [[ -z $AUR_HELPER ]]; then
            for spec in "${aur[@]}"; do fail "aur: $spec (no AUR helper)"; done
        else
            install_with aur_install aur "${aur[@]}"
        fi
    fi
}

configure_nvidia() {
    if ! has_vendor nvidia || ! group_selected gpu; then
        return 0
    fi
    step "NVIDIA"
    # niri wiki: stop the driver from keeping freed VRAM in niri's heap.
    local profile=/etc/nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json
    if [[ ! -f $profile ]]; then
        write_root_file "$profile" '{
    "rules": [
        {
            "pattern": { "feature": "procname", "matches": "niri" },
            "profile": "Limit Free Buffer Pool On Wayland Compositors"
        }
    ],
    "profiles": [
        {
            "name": "Limit Free Buffer Pool On Wayland Compositors",
            "settings": [ { "key": "GLVidHeapReuseRatio", "value": 0 } ]
        }
    ]
}'
        ok "nvidia: niri VRAM profile"
    fi
    # Arch wiki: without the kms hook nouveau cannot grab the GPU in early boot.
    local conf=/etc/mkinitcpio.conf
    if grep -Eq '^HOOKS=.*\bkms\b' "$conf" 2>/dev/null; then
        run sudo cp "$conf" "$conf.dotfile.bak"
        run sudo sed -i -E '/^HOOKS=/ { s/\bkms\b//; s/\( +/(/; s/ +\)/)/; s/ {2,}/ /g }' "$conf"
        if run sudo mkinitcpio -P; then
            ok "nvidia: removed kms hook, initramfs rebuilt"
        else
            fail "nvidia: mkinitcpio -P failed"
        fi
    fi
    note "NVIDIA: reboot to load the new driver"
}

configure_thinkpad() {
    if [[ ! -e /proc/acpi/ibm/fan ]] || grep -qsr 'fan_control=1' /etc/modprobe.d/; then
        return 0
    fi
    step "ThinkPad fan control (niri/thfn_)"
    write_root_file /etc/modprobe.d/thinkpad_acpi.conf 'options thinkpad_acpi fan_control=1'
    ok "thinkpad_acpi: fan_control=1"
    note "ThinkPad fan control works after a reboot"
}

enable_services() {
    if [[ ! -d /run/systemd/system ]]; then
        return 0
    fi
    if pacman -Q bluez >/dev/null 2>&1 && ! systemctl is-enabled --quiet bluetooth.service 2>/dev/null; then
        if run sudo systemctl enable --now bluetooth.service; then
            ok "systemd: bluetooth.service"
        else
            warn "could not enable bluetooth.service"
        fi
    fi
}

# ---------------------------------------------------------------- configs

backup_path() {
    local target=$1 dest
    dest="$BACKUP_ROOT/$STAMP/${target#"$HOME"/}"
    if run mkdir -p "$(dirname "$dest")" && run mv "$target" "$dest"; then
        info "backed up $target -> $dest"
        return 0
    fi
    return 1
}

link_one() {
    local src=$1 dst=$2
    if [[ -L $dst && $(readlink "$dst") == "$src" ]]; then
        ok "linked: ${dst/#"$HOME"/\~}"
        return 0
    fi
    if [[ -e $dst || -L $dst ]] && ! backup_path "$dst"; then
        fail "could not back up $dst, not linked"
        return 0
    fi
    if run ln -s "$src" "$dst"; then
        ok "linked: ${dst/#"$HOME"/\~}"
    else
        fail "could not link $dst"
    fi
}

link_configs() {
    step "Linking configs into ~/.config"
    run mkdir -p "$HOME/.config" || die "cannot create ~/.config"
    local src name
    for src in "$REPO_DIR"/.config/*; do
        name=${src##*/}
        if [[ " ${LINK_EXCLUDE[*]} " == *" $name "* ]]; then
            continue
        fi
        link_one "$src" "$HOME/.config/$name"
    done
}

latest_backup() {
    local candidates=("$BACKUP_ROOT"/*/"$1")
    if [[ ${#candidates[@]} -gt 0 ]]; then
        printf '%s\n' "${candidates[-1]}"
    fi
}

unlink_configs() {
    step "Removing config symlinks"
    local src name dst backup
    for src in "$REPO_DIR"/.config/*; do
        name=${src##*/}
        dst=$HOME/.config/$name
        if [[ ! -L $dst || $(readlink "$dst") != "$src" ]]; then
            continue
        fi
        run rm "$dst"
        ok "unlinked: ~/.config/$name"
        backup=$(latest_backup ".config/$name")
        if [[ -n $backup ]]; then
            run mv "$backup" "$dst"
            ok "restored: ~/.config/$name from $backup"
        fi
    done
}

clone_or_update() {
    local url=$1 dir=$2
    if [[ -d $dir/.git ]]; then
        if run git -C "$dir" pull --ff-only -q; then
            ok "updated: ${dir/#"$HOME"/\~}"
        else
            warn "could not update $dir"
        fi
        return 0
    fi
    if [[ -d $dir && -n $(ls -A "$dir") ]]; then
        warn "$dir exists and is not a git checkout, left alone"
        return 0
    fi
    if [[ -d $dir ]] && ! run rmdir "$dir"; then
        fail "could not replace the empty directory $dir"
        return 0
    fi
    if run git clone -q --depth 1 "$url" "$dir"; then
        ok "cloned: ${dir/#"$HOME"/\~}"
    else
        fail "git clone $url"
    fi
}

setup_neovim() {
    if ! command -v nvim >/dev/null; then
        return 0
    fi
    local data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
    if [[ ! -f $data/site/autoload/plug.vim ]] &&
        ! run curl -fsSLo "$data/site/autoload/plug.vim" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
        warn "vim-plug download failed"
        return 0
    fi
    if [[ $DRY_RUN == 1 ]]; then
        run nvim --headless +'PlugInstall --sync' +qa
        return 0
    fi
    # nvim exits 0 either way, and the first start complains about the
    # not yet installed colorscheme, so judge by the plugin directory.
    timeout 300 nvim --headless +'PlugInstall --sync' +qa >/dev/null 2>&1 || true
    if [[ -n $(ls -A "$data/plugged" 2>/dev/null) ]]; then
        ok "nvim: plugins installed"
    else
        warn "nvim: PlugInstall failed, run :PlugInstall by hand"
    fi
}

cursor_theme() {
    sed -n 's/^[[:space:]]*xcursor-theme[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_DIR/.config/niri/config.kdl" | head -n 1
}

apply_gsettings() {
    if ! command -v gsettings >/dev/null; then
        return 0
    fi
    # Without a session bus gsettings silently writes to memory only.
    local -a bus=()
    if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]] && command -v dbus-run-session >/dev/null; then
        bus=(dbus-run-session --)
    fi
    local key value cursor
    cursor=$(cursor_theme)
    while read -r key value; do
        [[ -n $value ]] || continue
        if run "${bus[@]}" gsettings set org.gnome.desktop.interface "$key" "$value" 2>/dev/null; then
            ok "gsettings: $key=$value"
        else
            warn "gsettings: could not set $key"
        fi
    done <<EOF
color-scheme prefer-dark
gtk-theme adw-gtk3-dark
cursor-theme $cursor
cursor-size 24
EOF
}

set_login_shell() {
    local fish user shell
    fish=$(command -v fish) || return 0
    user=${USER:-$(id -un)}
    shell=$(getent passwd "$user" | cut -d: -f7)
    if [[ $shell == "$fish" ]]; then
        return 0
    fi
    if run sudo chsh -s "$fish" "$user"; then
        ok "login shell: fish"
    else
        fail "could not set fish as the login shell"
    fi
}

check_manual_bits() {
    local cursor dir found=0
    cursor=$(cursor_theme)
    for dir in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
        if [[ -d $dir/$cursor/cursors ]]; then
            found=1
        fi
    done
    if [[ -n $cursor && $found == 0 ]]; then
        if [[ $cursor == Remus* ]]; then
            note "Cursor $cursor is not on the AUR: download it from $REMUS_URL and unpack into ~/.local/share/icons/"
        else
            note "Cursor theme $cursor is not installed (niri/config.kdl)"
        fi
    fi

    local app missing=()
    for app in "${CUSTOM_APPS[@]}"; do
        command -v "$app" >/dev/null || missing+=("${app##*/}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        note "Your own apps bound in niri are not installed: ${missing[*]}"
    fi
}

setup_extras() {
    step "Extras"
    clone_or_update https://github.com/alexanderjeurissen/ranger_devicons "$HOME/.config/ranger/plugins/ranger_devicons"
    clone_or_update https://github.com/maximtrp/ranger-archives "$HOME/.config/ranger/plugins/ranger-archives"
    clone_or_update https://github.com/Ashwatthaamaa/Neuwaita "$HOME/.local/share/icons/Neuwaita"
    setup_neovim

    run mkdir -p "$HOME/Pictures/Screenshot" "$HOME/.local/share/Trash/files" || warn "could not create ~/Pictures/Screenshot"
    if command -v xdg-user-dirs-update >/dev/null; then
        run xdg-user-dirs-update || warn "xdg-user-dirs-update failed"
    fi
    if command -v fc-cache >/dev/null; then
        run fc-cache -f || warn "fc-cache failed"
    fi
    apply_gsettings
    set_login_shell
    check_manual_bits
}

# ---------------------------------------------------------------- main

summary() {
    step "Summary"
    info "done: ${#ok_list[@]}, warnings: ${#warn_list[@]}, failed: ${#fail_list[@]}"
    local item
    for item in "${warn_list[@]}"; do printf '  %sWARN%s  %s\n' "$C_YELLOW" "$C_RESET" "$item"; done
    for item in "${fail_list[@]}"; do printf '  %sFAIL%s  %s\n' "$C_RED" "$C_RESET" "$item"; done
    for item in "${note_list[@]}"; do printf '  NOTE  %s\n' "$item"; done
    if [[ -d $BACKUP_ROOT/$STAMP ]]; then
        printf '  NOTE  Old configs were moved to %s\n' "$BACKUP_ROOT/$STAMP"
    fi
    if [[ $DRY_RUN == 0 && $DO_UNLINK == 0 && ${#fail_list[@]} -eq 0 ]]; then
        printf '\n  Reboot, log in on tty1 and niri starts. Check with: %s/scripts/doctor.sh\n' "$REPO_DIR"
    fi
}

main() {
    find_local_repo
    parse_args "$@"
    if [[ $EUID -eq 0 ]]; then
        die "run as your normal user, not root; sudo is used where needed"
    fi
    if [[ -z $REPO_DIR ]]; then
        bootstrap "$@"
    fi

    if [[ $DO_UNLINK == 1 ]]; then
        unlink_configs
    else
        if [[ $DO_PACKAGES == 1 ]]; then
            preflight
            start_sudo
            enable_multilib
            system_upgrade
            ensure_aur_helper
            install_packages
            configure_nvidia
            configure_thinkpad
            enable_services
        fi
        if [[ $DO_CONFIGS == 1 ]]; then
            link_configs
            setup_extras
        fi
    fi

    summary
    if [[ ${#fail_list[@]} -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
