# Octavich Dotfiles

Arch Linux dotfiles for a niri Wayland session with fish, Waybar, PipeWire,
desktop portals, GTK settings and optional NVIDIA setup.

## Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/octavich/.dotfile/main/install.sh)"
```

Local clone:

```bash
./install.sh
```

Run checks without changing the system:

```bash
./install.sh --check
```

## swww

`swww` is built from upstream GitHub source instead of AUR/package metadata:

```text
https://github.com/LGFae/swww
```

The installer clones `SWWW_REPO_URL`, checks out `SWWW_VERSION`, runs
`cargo build --release`, then installs:

```text
/usr/local/bin/swww
/usr/local/bin/swww-daemon
```

Defaults:

```bash
SWWW_REPO_URL=https://github.com/LGFae/swww.git
SWWW_VERSION=v0.11.2
```

Optional AUR packages are skipped by default. `pwvucontrol` is optional because
it can temporarily fail to build on rolling Arch when upstream PipeWire/spa
bindings change. Use `pavucontrol` as the stable fallback.

```bash
./install.sh --with-optional-aur
INSTALL_OPTIONAL_AUR=1 ./install.sh
```

AUR package review stays enabled by default. The installer exports
`EDITOR=micro` and `VISUAL=micro` so `paru` does not drop you into vim. If you
explicitly want non-interactive AUR installs:

```bash
AUR_SKIP_REVIEW=1 ./install.sh
```

NVIDIA is auto-detected. Modern GPUs use `nvidia-open` by default:

```bash
./install.sh --nvidia
./install.sh --nvidia-driver=proprietary
./install.sh --no-nvidia
```

greetd + tuigreet is the default login flow:

```bash
./install.sh --session=greetd
```

TTY login is still supported:

```bash
./install.sh --session=tty
```

## Session Startup

The default login flow is greetd + tuigreet:

1. Boot to `graphical.target`.
2. greetd starts tuigreet on `tty1`.
3. tuigreet starts `/usr/local/bin/dotfile-niri-session`.
4. the wrapper executes `niri-session`.

The installer writes `/etc/greetd/config.toml` directly and enables
`greetd.service`. It intentionally does not use `tuigreet --remember-session`,
because remembered session choices can override the configured `--cmd` and
start the wrong niri entry.

TTY mode remains available with `--session=tty`:

1. Boot to TTY.
2. Log in on `tty1`.
3. fish runs as the login shell.
4. `config/fish/config.fish` executes `niri-session`.

Do not start niri by running plain `niri` from a login shell. Use
`niri-session`, because it sets up the session correctly.

## NVIDIA

For NVIDIA systems the installer installs:

- `nvidia-open` and `nvidia-utils` by default.
- `nvidia` and `nvidia-utils` when `--nvidia-driver=proprietary` is used.
- `lib32-nvidia-utils` for multilib compatibility.
- `libva-nvidia-driver` as an optional package.

When `/etc/default/grub` exists, the installer adds this kernel parameter
without duplicating it:

```text
nvidia-drm.modeset=1
```

Then it runs:

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo mkinitcpio -P
```

For systemd-boot the installer does not edit loader entries automatically. Add
`nvidia-drm.modeset=1` to the entry `options` line manually.

Verify after reboot:

```bash
cat /proc/cmdline
lsmod | grep -E 'nvidia|nvidia_drm|nvidia_modeset'
```

## PipeWire Audio

The installer installs and enables user services:

```bash
systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
```

If this runs before a user systemd session is available, the installer prints a
post-install command instead of failing silently.

Verify:

```bash
pactl info
systemctl --user status pipewire pipewire-pulse wireplumber
pavucontrol
```

`pactl info` should show:

```text
Server Name: PulseAudio (on PipeWire ...)
```

## Multilib

The installer always enables the Arch `[multilib]` repository because this setup
is intended for the author's desktop use, including Wine/Proton/Steam-style
compatibility. It backs up `/etc/pacman.conf`, enables the repository
idempotently, then syncs package databases.

Baseline 32-bit packages include:

- `lib32-pipewire`
- `lib32-libpulse`
- `lib32-alsa-plugins`
- `lib32-vulkan-icd-loader`
- `lib32-nvidia-utils` on NVIDIA systems

## Portals

The required portal packages are:

- `xdg-desktop-portal`
- `xdg-desktop-portal-gtk`

The niri config does not impersonate GNOME. It sets:

```text
XDG_CURRENT_DESKTOP=niri
XDG_SESSION_DESKTOP=niri
XDG_SESSION_TYPE=wayland
```

At niri startup the config imports the graphical environment into the DBus and
systemd user activation environments:

```bash
dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
```

Verify:

```bash
systemctl --user show-environment | grep -E 'XDG_CURRENT_DESKTOP|XDG_SESSION_DESKTOP|XDG_SESSION_TYPE|WAYLAND_DISPLAY|DISPLAY'
systemctl --user status xdg-desktop-portal xdg-desktop-portal-gtk
```

`xdg-desktop-portal-gnome` is optional. It is not required for the base setup and
the session must not set `XDG_CURRENT_DESKTOP=gnome` unless GNOME is actually
running.

## XWayland

The installer installs `xwayland-satellite` for X11-only GUI applications such
as Avalonia-based tools. Modern niri integrates with `xwayland-satellite`
automatically when it is available in `PATH`, so the config does not fake
`DISPLAY` and does not start a duplicate `xwayland-satellite` process manually.

The config does not fake `DISPLAY=:0`. Check the real environment:

```bash
echo $WAYLAND_DISPLAY
echo $DISPLAY
ps aux | grep -Ei 'xwayland|xwayland-satellite'
```

## GTK

GTK dark mode is configured through `settings.ini` and `gsettings`. The repo
does not ship a GTK4 `gtk.css` that imports Adwaita resource files. Those
imports are not stable across GTK/libadwaita versions and can break
applications.

The installer does not apply GNOME `gsettings` by default, because this setup is
a niri session and global GTK/XSettings overrides can break launcher visuals. If
you explicitly want those settings:

```bash
APPLY_GSETTINGS=1 ./install.sh
```

## Troubleshooting

If niri does not start from `tty1`:

```bash
echo $SHELL
tty
command -v niri-session
```

Set fish as the login shell if needed:

```bash
chsh -s "$(command -v fish)"
```

If greetd/tuigreet accepts the password but opens a black niri screen, verify
that tuigreet is not using an old remembered session:

```bash
sudo cat /etc/greetd/config.toml
sudo rm -f /var/cache/tuigreet/*session*
sudo systemctl restart greetd.service
```

The expected command is:

```toml
command = "tuigreet --time --asterisks --remember --cmd /usr/local/bin/dotfile-niri-session"
```

If PipeWire is not active:

```bash
systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
systemctl --user status pipewire pipewire-pulse wireplumber
```

If portals fail with `cannot open display`, verify the niri startup environment
import and check:

```bash
systemctl --user show-environment
echo $WAYLAND_DISPLAY
echo $DISPLAY
```

If an optional AUR package fails, read the installer summary. Optional failures
do not make the install fail. Required package failures are listed separately and
make the script exit with status `1`.

## Doctor

After reboot, run:

```bash
~/.dotfile/scripts/doctor.sh
```

It checks:

- `niri-session`, `swww`, `swww-daemon` and `xwayland-satellite`;
- imported systemd user environment;
- PipeWire and PulseAudio compatibility;
- desktop portals;
- XWayland environment;
- NVIDIA cmdline and modules when NVIDIA hardware is detected.
