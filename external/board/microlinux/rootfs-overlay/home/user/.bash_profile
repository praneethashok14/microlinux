# MicroLinux login shell. On tty1 the graphical desktop starts automatically
# (disable with the "ml.nox" boot option).
[ -f ~/.bashrc ] && . ~/.bashrc
if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ] && ! grep -qw ml.nox /proc/cmdline; then
	startx -- vt1 -keeptty -nolisten tcp > ~/.xsession.log 2>&1
	echo "The desktop has exited (log: ~/.xsession.log). Type 'startx' to start it again."
fi
