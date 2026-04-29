# Nix
if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    bass source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
end


set -g fish_greeting
set -gx EDITOR micro
set -gx VISUAL micro

if status is-interactive
    if command -q fastfetch; and test -z "$FASTFETCH_DISABLE"; and test "$TERM" != dumb
        fastfetch
    end

    alias ff fastfetch
    alias sww "$HOME/.config/sww.sh"

    bind \t accept-autosuggestion
end

if status is-login; and test -z "$WAYLAND_DISPLAY"; and test -z "$DISPLAY"; and test (tty) = "/dev/tty1"
    exec niri-session
end
