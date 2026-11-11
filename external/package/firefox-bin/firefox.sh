#!/bin/sh
# MicroLinux launcher for the official Firefox build (replaces Mozilla's
# "firefox" stub, which only runs firefox-bin).
# With a GPU render node, let Firefox pick hardware WebRender (it falls back
# to software rendering itself on blocklisted or software-only drivers);
# older /usr/bin/firefox wrappers force software rendering, so undo that.
if ls /dev/dri/renderD* >/dev/null 2>&1; then
	unset MOZ_WEBRENDER_SOFTWARE
fi
exec /opt/firefox/firefox-bin "$@"
