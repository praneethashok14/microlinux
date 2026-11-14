#!/bin/bash
# MicroLinux compatibility test suite for other systems' programs (TAP output)
#
#   el7-compat.sh [-n]      RHEL/CentOS 7 (7.9.2009)
#   el10-compat.sh [-n]     RHEL 10 (AlmaLinux 10.2)
#   deb-compat.sh [-n]      Debian 13.7
#                           -n: skip tests that need the network
#
# Runs real programs of that system (this system's architecture) from the
# el7-runtime / el10-runtime / debian-runtime package (/opt/el7, /opt/el10,
# /opt/debian) in two ways:
#   native:  executed directly - system glibc + compat libraries only
#   *-run:   executed with that system's glibc loader and libraries
# For each program it records the elfcheck verdict and checks the program's
# output against the expected result. A program "passes" if it produces the
# expected output in at least the mode elfcheck predicts.
NONET=; [ "$1" = -n ] && NONET=1
me=${0##*/}
case "$me" in
	el10-*) EL=10 R=/opt/el10 RUN=el10-run CHROOT=el10-chroot V=EL10-RUN pkg=el10-runtime ;;
	deb-*)  EL=deb R=/opt/debian RUN=deb-run CHROOT=deb-chroot V=DEB-RUN pkg=debian-runtime ;;
	*)      EL=7 R=/opt/el7 RUN=el7-run CHROOT=el7-chroot V=EL7-RUN pkg=el7-runtime ;;
esac
B=$R/usr/bin
n=0; fail=0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
echo "hello el$EL" > "$W/f.txt"

if [ ! -x "$B/bash" ]; then
	echo "1..1"; echo "not ok 1 - $pkg package is not active (mlpkg list)"; exit 1
fi

ok()   { n=$((n + 1)); echo "ok $n - $*"; }
nok()  { n=$((n + 1)); fail=$((fail + 1)); echo "not ok $n - $*"; }

# t NAME EXPECTED -- COMMAND...   (COMMAND's first word is an EL binary in $B)
t() {
	local name=$1 want=$2; shift 3
	local bin=$1; shift
	local verdict got_native got_el mode
	verdict=$(elfcheck "$B/$bin" 2>/dev/null | sed -n 's/.*verdict: *\([A-Z0-9-]*\).*/\1/p; s/.*: script (.*/NATIVE/p' | head -n1)
	got_native=$(cd "$W" && timeout 20 "$B/$bin" "$@" </dev/null 2>&1 | tr -d '\r' | tail -n 1)
	got_el=$(cd "$W" && timeout 20 $RUN "$B/$bin" "$@" </dev/null 2>&1 | tr -d '\r' | tail -n 1)
	local nat=no rt=no
	[[ "$got_native" == $want ]] && nat=yes
	[[ "$got_el" == $want ]] && rt=yes
	case "$verdict" in
		NATIVE)     [ $nat = yes ] && mode=pass || mode=fail ;;
		$V)         [ $rt = yes ] && mode=pass || mode=fail ;;
		*)          mode=fail ;;
	esac
	if [ $mode = pass ]; then ok "$name [elfcheck=$verdict native=$nat $RUN=$rt]"
	else nok "$name [elfcheck=$verdict native=$nat $RUN=$rt] expected '$want', native '$got_native', $RUN '$got_el'"; fi
}

case "$(uname -m)" in aarch64) farch='ARM aarch64' ;; x86_64) farch='x86-64' ;; *) farch=$(uname -m) ;; esac
printf '3\n1\n2\n' > "$W/nums"; printf abc > "$W/abc"; echo hello > "$W/hello"; printf '2^64\nquit\n' > "$W/calc"
echo "# glibc on this system: $(/usr/lib/libc.so.6 | sed -n '1s/.*version \([0-9.]*\).*/\1/p'), $pkg: $($RUN $B/getconf GNU_LIBC_VERSION 2>/dev/null)"

# tests both releases have (expected output differs per release)
common() { # bash-version gawk-version grep-lib readline-lib
	t "bash $1"                           "$1*"                      -- bash -c 'echo $BASH_VERSION'
	t "coreutils ls (libselinux, libcap)" "$W/f.txt"                 -- ls -d "$W/f.txt"
	t "coreutils sort"                    '3'                        -- sort "$W/nums"
	t "coreutils sha256sum"               'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad *' -- sha256sum "$W/abc"
	t "coreutils date"                    '1970'                     -- date -u -d @0 +%Y
	t "tree"                              '* director*, * files'     -- tree "$W"
	t "gawk (libmpfr, libgmp)"            '1024 3'                   -- gawk 'BEGIN { print 2^10, length("abc") }'
	t "gawk $2 PROCINFO"                  "$2*"                      -- gawk 'BEGIN { print PROCINFO["version"] }'
	t "sed (libselinux, libacl)"          'heLLo'                    -- sed 's/l/L/g' "$W/hello"
	t "grep ($3)"                         '1'                        -- grep -c "el$EL" "$W/f.txt"
	t "grep -P"                           "el$EL"                    -- grep -oP 'e\w+' "$W/f.txt"
	t "bc ($4)"                           '18446744073709551616'     -- bc -q "$W/calc"
	t "which"                             '*/bash'                   -- which bash
	t "find"                              "$W/f.txt"                 -- find "$W" -name f.txt
	t "file + libmagic"                   "*ELF 64-bit LSB*$farch*"  -- file /usr/bin/busybox
	t "zip"                               '*ing: f.txt*'             -- zip "$W/a.zip" f.txt
	t "unzip"                             '* 1 file'                 -- unzip -l "$W/a.zip"
}

# openssl s_client to a public server, verifying its certificate
tls() {
	if [ -n "$NONET" ]; then ok "openssl TLS handshake # SKIP no network"; return; fi
	local got
	got=$(timeout 30 $RUN "$B/openssl" s_client -connect www.mozilla.org:443 -servername www.mozilla.org \
		-CAfile /etc/pki/tls/certs/ca-bundle.crt -verify_return_error < /dev/null 2>&1 | grep -m1 'Verify return code')
	[[ "$got" == *'Verify return code: 0 (ok)'* ]] && ok "openssl $1 TLS handshake with certificate verification ($RUN)" \
		|| nok "openssl TLS handshake: got '$got'"
}

if [ "$EL" = 7 ]; then
	echo "1..20"
	common 4.2.46 4.0.2 libpcre.so.1 libreadline.so.6
	t "openssl 1.0.2k (libssl.so.10)"     'OpenSSL 1.0.2k-fips*'     -- openssl version
	tls 1.0.2k
	# full EL7 userspace
	if [ "$(id -u)" = 0 ]; then
		got=$(el7-chroot /bin/bash -c 'echo "$BASH_VERSION $(ls --version | head -n1)"' 2>&1 | tail -n1)
		[[ "$got" == '4.2.46'*'coreutils) 8.22' ]] && ok "el7-chroot: EL7 bash + coreutils userspace" || nok "el7-chroot: got '$got'"
	else
		ok "el7-chroot # SKIP needs root"
	fi
elif [ "$EL" = 10 ]; then
	echo "1..22"
	common 5.2.26 5.3 libpcre2-8.so.0 libreadline.so.8
	t "tar (libacl, libselinux)"          'f.txt'                    -- tar -cvf "$W/a.tar" -C "$W" f.txt
	t "curl 8 (libcurl)"                  "hello el$EL"              -- curl -s "file://$W/f.txt"
	t "openssl 3 (libssl.so.3)"           'OpenSSL 3.*'              -- openssl version
	tls 3
	# full EL10 userspace, and installing an RPM with rpm (dependencies are
	# checked against the runtime's rpm database)
	if [ "$(id -u)" != 0 ]; then
		ok "el10-chroot # SKIP needs root"
	elif [ -n "$NONET" ]; then
		got=$(el10-chroot /bin/bash -c 'echo "$BASH_VERSION $(rpm -q bash)"' 2>&1 | tail -n1)
		[[ "$got" == '5.2.26'*' bash-5.2.26-'* ]] && ok "el10-chroot: EL10 bash + rpm database (RPM install # SKIP no network)" \
			|| nok "el10-chroot: got '$got'"
	else
		case "$(uname -m)" in x86_64) a=x86_64_v2 ;; *) a=$(uname -m) ;; esac
		u=https://vault.almalinux.org/10.1/BaseOS/$a/os/Packages/hostname-3.23-14.el10.$a.rpm
		got=$(el10-chroot /bin/bash -c "curl -sSfo /tmp/h.rpm $u && rpm -ivh /tmp/h.rpm >/dev/null && rpm -q hostname && hostname -V 2>&1 | head -n1; rm -f /tmp/h.rpm" 2>&1 | tr '\n' ' ')
		[[ "$got" == *'hostname-3.23-14.el10'*'hostname 3.23'* ]] && ok "el10-chroot: AlmaLinux RPM installed with rpm -ivh (dependencies checked) and run" \
			|| nok "el10-chroot RPM install: got '$got'"
	fi
else
	echo "1..22"
	common 5.2.37 5.2.1 libpcre2-8.so.0 libreadline.so.8
	t "tar (libacl, libselinux)"          'f.txt'                    -- tar -cvf "$W/a.tar" -C "$W" f.txt
	t "curl 8 (libcurl)"                  "hello el$EL"              -- curl -s "file://$W/f.txt"
	t "openssl 3 (libssl.so.3)"           'OpenSSL 3.*'              -- openssl version
	tls 3
	# full Debian userspace, and installing a .deb with dpkg (dependencies are
	# checked against the runtime's dpkg database)
	if [ "$(id -u)" != 0 ]; then
		ok "deb-chroot # SKIP needs root"
	elif [ -n "$NONET" ]; then
		got=$(deb-chroot /bin/bash -c 'echo "$BASH_VERSION $(dpkg-query -W -f="\${Version}" bash)"' 2>&1 | tail -n1)
		[[ "$got" == '5.2.37'*' 5.2.37-'* ]] && ok "deb-chroot: Debian bash + dpkg database (.deb install # SKIP no network)" \
			|| nok "deb-chroot: got '$got'"
	else
		case "$(uname -m)" in x86_64) a=amd64 ;; aarch64) a=arm64 ;; esac
		u=https://snapshot.debian.org/archive/debian/20260913T000000Z/pool/main/h/hostname/hostname_3.25_$a.deb
		got=$(deb-chroot /bin/bash -c "curl -sSfLo /tmp/h.deb $u && dpkg -i /tmp/h.deb >/dev/null && dpkg-query -W hostname && hostname -V 2>&1 | head -n1; rm -f /tmp/h.deb" 2>&1 | tr '\n\t' '  ')
		[[ "$got" == *'hostname 3.25 hostname 3.25'* ]] && ok "deb-chroot: Debian .deb installed with dpkg -i (dependencies checked) and run" \
			|| nok "deb-chroot .deb install: got '$got'"
	fi
fi
echo "# $((n - fail))/$n passed"
[ $fail = 0 ]
