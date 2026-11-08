#!/bin/sh
# MicroLinux X session
export XENVIRONMENT="$HOME/.Xresources"
# keyboard layout: ml.keymap= on the kernel command line, else the one chosen in Settings
kb=$(sed -n 's/.*ml\.keymap=\([a-z]*\).*/\1/p' /proc/cmdline)
[ -n "$kb" ] || kb=$(cat "$HOME/.config/microlinux/keyboard" 2>/dev/null)
setxkbmap "${kb:-us}"
xsetroot -cursor_name left_ptr
ml-display auto
if command -v dbus-run-session >/dev/null; then exec dbus-run-session jwm; fi
exec jwm
