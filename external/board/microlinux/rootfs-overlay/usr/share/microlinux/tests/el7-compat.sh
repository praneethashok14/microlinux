#!/bin/bash
# MicroLinux EL7 compatibility test suite (TAP output)
#
#   el7-compat.sh [-n]      -n: skip tests that need the network
#
# Runs real RHEL/CentOS 7 (7.9.2009, this system's architecture) programs from the
# el7-runtime package (/opt/el7) in two ways:
#   native:  executed directly - system glibc + compat libraries only
#   el7-run: executed with the EL7 glibc 2.17 loader and libraries
# For each program it records the elfcheck verdict and checks the program's
# output against the expected result. A program "passes" if it produces the
# expected output in at least the mode elfcheck predicts.
NONET=; [ "$1" = -n ] && NONET=1
R=/opt/el7
B=$R/usr/bin
n=0; fail=0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
echo "hello el7" > "$W/f.txt"

if [ ! -x "$B/bash" ]; then
	echo "1..1"; echo "not ok 1 - el7-runtime package is not active (mlpkg list)"; exit 1
fi

ok()   { n=$((n + 1)); echo "ok $n - $*"; }
nok()  { n=$((n + 1)); fail=$((fail + 1)); echo "not ok $n - $*"; }

# t NAME EXPECTED -- COMMAND...   (COMMAND's first word is an EL7 binary in $B)
t() {
	local name=$1 want=$2; shift 3
	local bin=$1; shift
	local verdict got_native got_el7 mode
	verdict=$(elfcheck "$B/$bin" 2>/dev/null | sed -n 's/.*verdict: *\([A-Z0-9-]*\).*/\1/p' | head -n1)
	got_native=$(cd "$W" && timeout 20 "$B/$bin" "$@" </dev/null 2>&1 | tr -d '\r' | tail -n 1)
	got_el7=$(cd "$W" && timeout 20 el7-run "$B/$bin" "$@" </dev/null 2>&1 | tr -d '\r' | tail -n 1)
	local nat=no e7=no
	[[ "$got_native" == $want ]] && nat=yes
	[[ "$got_el7" == $want ]] && e7=yes
	case "$verdict" in
		NATIVE)  [ $nat = yes ] && mode=pass || mode=fail ;;
		EL7-RUN) [ $e7 = yes ] && mode=pass || mode=fail ;;
		*)       mode=fail ;;
	esac
	if [ $mode = pass ]; then ok "$name [elfcheck=$verdict native=$nat el7-run=$e7]"
	else nok "$name [elfcheck=$verdict native=$nat el7-run=$e7] expected '$want', native '$got_native', el7-run '$got_el7'"; fi
}

echo "# glibc on this system: $(/usr/lib/libc.so.6 | sed -n '1s/.*version \([0-9.]*\).*/\1/p'), EL7 runtime: $(ls $R/usr/lib64/libc-2.*.so | sed 's/.*libc-\(.*\)\.so/\1/')"
echo "1..20"
printf '3\n1\n2\n' > "$W/nums"; printf abc > "$W/abc"; echo hello > "$W/hello"; printf '2^64\nquit\n' > "$W/calc"
t "bash 4.2 (libtinfo.so.5)"          '4.2.46*'                  -- bash -c 'echo $BASH_VERSION'
t "coreutils ls (libselinux, libcap)" "$W/f.txt"                 -- ls -d "$W/f.txt"
t "coreutils sort"                    '3'                        -- sort "$W/nums"
t "coreutils sha256sum"               'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad *' -- sha256sum "$W/abc"
t "coreutils date"                    '1970'                     -- date -u -d @0 +%Y
t "tree"                              '0 directories, * files'   -- tree "$W"
t "gawk (libmpfr.so.4, libgmp.so.10)" '1024 3'                   -- gawk 'BEGIN { print 2^10, length("abc") }'
t "gawk 4.0.2 PROCINFO"               '4.0.2'                    -- gawk 'BEGIN { print PROCINFO["version"] }'
t "sed (libselinux, libacl)"          'heLLo'                    -- sed 's/l/L/g' "$W/hello"
t "grep (libpcre.so.1)"               '1'                        -- grep -c el7 "$W/f.txt"
t "grep -P (pcre)"                    'el7'                      -- grep -oP 'e\w7' "$W/f.txt"
t "bc (libreadline.so.6)"             '18446744073709551616'     -- bc -q "$W/calc"
t "which"                             '*/bash'                   -- which bash
t "find"                              "$W/f.txt"                 -- find "$W" -name f.txt
case "$(uname -m)" in aarch64) farch='ARM aarch64' ;; x86_64) farch='x86-64' ;; *) farch=$(uname -m) ;; esac
t "file + libmagic"                   "*ELF 64-bit LSB*$farch*"  -- file /usr/bin/busybox
t "zip"                               '*ing: f.txt*'             -- zip "$W/a.zip" f.txt
t "unzip"                             '* 1 file'                 -- unzip -l "$W/a.zip"
t "openssl 1.0.2k (libssl.so.10)"     'OpenSSL 1.0.2k-fips*'     -- openssl version
if [ -n "$NONET" ]; then
	ok "openssl TLS handshake # SKIP no network"
else
	got=$(timeout 30 el7-run "$B/openssl" s_client -connect www.mozilla.org:443 -servername www.mozilla.org \
		-CAfile /etc/pki/tls/certs/ca-bundle.crt -verify_return_error < /dev/null 2>&1 | grep -m1 'Verify return code')
	[[ "$got" == *'Verify return code: 0 (ok)'* ]] && ok "openssl 1.0.2k TLS handshake with certificate verification (el7-run)" \
		|| nok "openssl TLS handshake: got '$got'"
fi
# full EL7 userspace
if [ "$(id -u)" = 0 ]; then
	got=$(el7-chroot /bin/bash -c 'echo "$BASH_VERSION $(ls --version | head -n1)"' 2>&1 | tail -n1)
	[[ "$got" == '4.2.46'*'coreutils) 8.22' ]] && ok "el7-chroot: EL7 bash + coreutils userspace" || nok "el7-chroot: got '$got'"
else
	ok "el7-chroot # SKIP needs root"
fi
echo "# $((n - fail))/$n passed"
[ $fail = 0 ]
