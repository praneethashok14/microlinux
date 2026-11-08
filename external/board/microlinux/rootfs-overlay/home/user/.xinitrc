#!/bin/sh
# MicroLinux X session
export XENVIRONMENT="$HOME/.Xresources"
setxkbmap "$(sed -n 's/.*ml\.keymap=\([a-z]*\).*/\1/p' /proc/cmdline | grep . || echo us)"
xsetroot -cursor_name left_ptr
ml-display auto
if command -v dbus-run-session >/dev/null; then exec dbus-run-session jwm; fi
exec jwm
