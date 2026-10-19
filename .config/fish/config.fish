set -g fish_greeting

set -gx EDITOR nvim
set -gx VISUAL nvim

# Login on tty1 starts niri (no display manager).
if status is-login; and test -z "$WAYLAND_DISPLAY"; and test -z "$DISPLAY"; and test (tty) = /dev/tty1
    exec niri-session
end

if status is-interactive
    if command -q starship
        starship init fish | source
    end

    if command -q fastfetch; and test "$TERM" != dumb
        fastfetch
    end

    alias ff fastfetch
end
