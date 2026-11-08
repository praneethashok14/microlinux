#!/bin/sh
# Show MicroLinux build progress as a bar.
#   ./scripts/progress.sh [ARCH]       once (ARCH: aarch64 or x86_64, default x86_64
#                                      while it is building, else aarch64)
#   ./scripts/progress.sh -w [ARCH]    refresh every 10 s (Ctrl-C to stop)
VM=${VM:-builder}
W=; [ "$1" = -w ] && { W=1; shift; }
A=$1
show() {
	limactl shell "$VM" env A="$A" bash -c '
		if [ -z "$A" ]; then
			pgrep -f "O=/mnt/lima-mlbuild/out-x86_64" >/dev/null && A=x86_64 || A=aarch64
		fi
		[ "$A" = aarch64 ] && O=/mnt/lima-mlbuild/out || O=/mnt/lima-mlbuild/out-$A
		cd "$O" 2>/dev/null || { echo "no $A build yet"; exit; }
		total=$(ls -d build/*/ 2>/dev/null | wc -l)
		[ "$total" -lt 275 ] && total=275
		done=$(ls build/*/.stamp_installed build/*/.stamp_host_installed build/*/.stamp_target_installed \
			build/*/.stamp_images_installed 2>/dev/null | xargs -r -n1 dirname | sort -u | wc -l)
		pct=$((done * 100 / total)); w=40; f=$((pct * w / 100))
		bar=$(printf "%${f}s" | tr " " "#")$(printf "%$((w - f))s" | tr " " "-")
		now=$(grep -a "^>>>" build.log | tail -n1 | cut -c5-70)
		if grep -aqE "make: \*\*\* .* Error" build.log; then st="FAILED"
		elif [ -f images/microlinux-$A.iso ] && ! pgrep -x make >/dev/null; then st="DONE"; pct=100; bar=$(printf "%${w}s" | tr " " "#")
		elif pgrep -x make >/dev/null; then st="building"; else st="stopped"; fi
		printf "\r%-7s [%s] %3d%%  %d/%d  %-8s %-55s" "$A" "$bar" "$pct" "$done" "$total" "$st" "$now"'
}
if [ -n "$W" ]; then
	while :; do show; sleep 10; done
else
	show; echo
fi
