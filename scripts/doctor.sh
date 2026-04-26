#!/usr/bin/env bash

set -Eeuo pipefail

failed_checks=()
warned_checks=()

pass() {
    printf 'PASS: %s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
    warned_checks+=("$*")
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    failed_checks+=("$*")
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_command() {
    local command_name=$1

    if command_exists "$command_name"; then
        pass "command exists: $command_name"
    else
        fail "missing command: $command_name"
    fi
}

check_systemd_user_env() {
    if ! command_exists systemctl; then
        fail "systemctl is missing"
        return
    fi

    local env_output
    if ! env_output=$(systemctl --user show-environment 2>/dev/null); then
        fail "systemd user environment is not available"
        return
    fi

    local required_env=(
        XDG_CURRENT_DESKTOP=niri
        XDG_SESSION_DESKTOP=niri
        XDG_SESSION_TYPE=wayland
    )

    local env_pair
    for env_pair in "${required_env[@]}"; do
        if grep -qx "$env_pair" <<< "$env_output"; then
            pass "systemd user env: $env_pair"
        else
            fail "systemd user env missing: $env_pair"
        fi
    done

    if grep -q '^WAYLAND_DISPLAY=' <<< "$env_output"; then
        pass "systemd user env has WAYLAND_DISPLAY"
    else
        fail "systemd user env missing WAYLAND_DISPLAY"
    fi

    if grep -q '^DISPLAY=' <<< "$env_output"; then
        pass "systemd user env has DISPLAY"
    else
        warn "systemd user env has no DISPLAY; XWayland may not be active yet"
    fi
}

check_user_service() {
    local service_name=$1

    if systemctl --user is-active --quiet "$service_name"; then
        pass "user service active: $service_name"
    else
        fail "user service is not active: $service_name"
    fi
}

check_pipewire() {
    check_user_service pipewire.service
    check_user_service pipewire-pulse.service
    check_user_service wireplumber.service

    if ! command_exists pactl; then
        fail "pactl is missing"
        return
    fi

    local pactl_info
    if ! pactl_info=$(pactl info 2>/dev/null); then
        fail "pactl info failed"
        return
    fi

    if grep -q 'Server Name: PulseAudio (on PipeWire' <<< "$pactl_info"; then
        pass "PulseAudio compatibility is served by PipeWire"
    else
        fail "pactl does not report PulseAudio on PipeWire"
    fi
}

check_portals() {
    local service_name
    for service_name in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
        if systemctl --user is-failed --quiet "$service_name"; then
            fail "portal service is failed: $service_name"
        elif systemctl --user is-active --quiet "$service_name"; then
            pass "portal service active: $service_name"
        else
            warn "portal service is not active now: $service_name; it may start on DBus activation"
        fi
    done
}

check_xwayland() {
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        pass "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    else
        fail "WAYLAND_DISPLAY is empty"
    fi

    if [ -n "${DISPLAY:-}" ]; then
        pass "DISPLAY=$DISPLAY"
    else
        warn "DISPLAY is empty; XWayland apps may not work"
    fi

    if pgrep -af 'xwayland|xwayland-satellite' >/dev/null 2>&1; then
        pass "XWayland/xwayland-satellite process is running"
    else
        warn "No XWayland/xwayland-satellite process found"
    fi
}

has_nvidia_gpu() {
    if command_exists lspci && lspci | grep -Ei 'nvidia|3d controller|vga' | grep -qi nvidia; then
        return 0
    fi

    if [ -d /sys/bus/pci/devices ] && grep -Rqi '^0x10de$' /sys/bus/pci/devices/*/vendor 2>/dev/null; then
        return 0
    fi

    return 1
}

check_nvidia() {
    if ! has_nvidia_gpu; then
        warn "NVIDIA GPU not detected; skipping NVIDIA checks"
        return
    fi

    if grep -qw 'nvidia-drm.modeset=1' /proc/cmdline; then
        pass "kernel cmdline has nvidia-drm.modeset=1"
    else
        fail "kernel cmdline is missing nvidia-drm.modeset=1"
    fi

    local module_name
    for module_name in nvidia nvidia_drm nvidia_modeset; do
        if lsmod | awk '{print $1}' | grep -qx "$module_name"; then
            pass "NVIDIA module loaded: $module_name"
        else
            fail "NVIDIA module missing: $module_name"
        fi
    done
}

main() {
    check_command niri-session
    check_command swww
    check_command swww-daemon
    check_command xwayland-satellite
    check_systemd_user_env
    check_pipewire
    check_portals
    check_xwayland
    check_nvidia

    printf '\nDoctor summary\n'
    printf 'Warnings: %d\n' "${#warned_checks[@]}"
    printf 'Failures: %d\n' "${#failed_checks[@]}"

    if [ "${#failed_checks[@]}" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
