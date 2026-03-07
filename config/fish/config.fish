# Nix
if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    bass source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
end


set -g fish_greeting
fastfetch

if status is-interactive
    # Commands to run in interactive sessions can go here
    alias ff fastfetch
    alias sww "$HOME/.config/sww.sh"

    bind \t accept-autosuggestion
end


# Start
if test -z $DISPLAY; and test (tty) = "/dev/tty1"
    dbus-run-session  niri --session
end

