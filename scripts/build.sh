#!/bin/sh
# Build MicroLinux. Run on the Mac; the work happens in the Lima VM "builder",
# on the ext4 build disk stored in ./build-disk.img (mounted at /mnt/lima-mlbuild).
#
#   ./scripts/build.sh                      build both architectures (incremental)
#   ./scripts/build.sh --arch x86_64        build one: aarch64 | x86_64 | all
#   ./scripts/build.sh --arch x86_64 <target>
#                                           any Buildroot target, e.g. menuconfig,
#                                           linux-rebuild, lxqt-panel-dirclean, savedefconfig
# Results: out/microlinux-<arch>.iso, out/microlinux-<arch>-base.iso,
#          out/size-report-<arch>.txt, and the package repository in
#          ../microlinux-repo/<arch>/ (REPO_DIR=... to change; publish with
#          scripts/publish-repo.sh)
set -e
cd "$(dirname "$0")/.."
SRC="$PWD"
VM=${VM:-builder}
REPO_DIR=${REPO_DIR:-$(cd .. && pwd)/microlinux-repo}
ARCHES="aarch64 x86_64"
if [ "$1" = --arch ]; then
	case "$2" in
		all) ;;
		aarch64|x86_64) ARCHES=$2 ;;
		*) echo "unknown arch '$2' (aarch64, x86_64, all)"; exit 1 ;;
	esac
	shift 2
fi
limactl list -q 2>/dev/null | grep -qx "$VM" || { echo "Lima VM '$VM' missing - see docs/BUILD.md"; exit 1; }
[ "$(limactl list --format '{{.Status}}' "$VM")" = Running ] || limactl start "$VM"
./scripts/gen-defconfigs.sh
# build ID (/etc/microlinux-build, BUILD-<arch>): what "mlpkg system-update" compares
ML_BUILD_ID="$(date -u +%Y%m%d.%H%M)-$(git rev-parse --short HEAD 2>/dev/null || echo nogit)$(git diff --quiet HEAD 2>/dev/null || echo +)"

limactl shell "$VM" env SRC="$SRC" ARCHES="$ARCHES" TARGET="$*" ML_BUILD_ID="$ML_BUILD_ID" bash -s <<'VMEOF'
set -e
W=/mnt/lima-mlbuild
BR=$W/buildroot
# Buildroot cannot handle spaces in paths, so mirror the source tree onto the build disk.
rsync -a --delete --exclude build-disk.img --exclude out --exclude tests/.run --exclude release-base "$SRC/" "$W/src/"
# the last release's images (scripts/mark-released.sh): the small update is made against them
export ML_RELEASE_BASE="$SRC/release-base"
export BR2_DL_DIR=$W/dl
# LLVM (Mesa's GPU drivers) needs 1-2 GB per C++ compile: swap on the build
# disk so that parallel compiles don't run the 8 GB VM out of memory
if ! swapon --show=NAME --noheadings | grep -q "$W/swapfile"; then
	[ -f $W/swapfile ] || { sudo fallocate -l 6G $W/swapfile && sudo chmod 600 $W/swapfile && sudo mkswap -q $W/swapfile; }
	sudo swapon $W/swapfile
fi
cd "$BR"
for A in $ARCHES; do
	# aarch64 keeps the original output directory, so existing builds stay incremental
	if [ "$A" = aarch64 ]; then O=$W/out; else O=$W/out-$A; fi
	echo "===== MicroLinux $A ($O)"
	if [ -n "$TARGET" ]; then
		[ -f "$O/.config" ] || make O="$O" BR2_EXTERNAL="$W/src/external" microlinux_${A}_defconfig
		make O="$O" $TARGET
		continue
	fi
	# the defconfig in the repo is the source of truth: re-apply it every build
	make O="$O" BR2_EXTERNAL="$W/src/external" microlinux_${A}_defconfig >/dev/null
	# With per-package directories, target-finalize assembles target/ from the
	# packages every time, but never deletes: start from an empty one so that
	# renamed or removed overlay files and moved repository files can't linger.
	rm -rf "${O:?}/target"
	# per-package directories keep copies of dependencies as they were when
	# each package was built: bring copies of rebuilt packages up to date, or
	# an old copy can end up in the image (e.g. Mesa without iris)
	python3 "$W/src/external/board/microlinux/ppd-refresh.py" "$O" | tail -n 1
	# Buildroot copies a local-source package once and doesn't notice later
	# changes: rebuild ours when their source changed
	for p in ml-settings ml-software ml-installer; do
		h=$(cd "$W/src/external/package/$p" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum | cut -c1-16)
		[ "$(cat "$O/.ml-src-$p" 2>/dev/null)" = "$h" ] && continue
		make O="$O" "$p-dirclean" >/dev/null
		echo "$h" > "$O/.ml-src-$p"
	done
	set -o pipefail
	if ! make -j"$(nproc)" O="$O" 2>&1 | tee "$O/build.log" | { grep --line-buffered -E '^>>>|Error|error:' || true; }; then
		echo "BUILD FAILED ($A) - see $O/build.log"; tail -40 "$O/build.log"; exit 1
	fi
	mkdir -p "$SRC/out"
	# copy then rename, so a VM still running the previous ISO keeps its (old) file
	for f in microlinux-$A.iso microlinux-$A-base.iso size-report.txt SHA256SUMS-$A SHA256SUMS-$A.asc SHA256SUMS-$A.sig BUILD-$A ml-system-update; do
		[ -f "$O/images/$f" ] || continue
		dst=$f; [ "$f" = size-report.txt ] && dst=size-report-$A.txt
		cp "$O/images/$f" "$SRC/out/.$dst.new" && mv -f "$SRC/out/.$dst.new" "$SRC/out/$dst"
	done
	rm -f "$SRC/out/update-$A-from-"*.tar.zst
	for f in "$O/images/update-$A-from-"*.tar.zst; do
		[ -f "$f" ] && cp "$f" "$SRC/out/"
	done
	# package repository: handed over through out/ (the only folder the VM sees)
	[ -f "$O/images/repo/INDEX" ] && rsync -a --delete "$O/images/repo/" "$SRC/out/.repo-$A/"
done
[ -n "$TARGET" ] || ls -lh "$SRC/out/"
VMEOF

[ -n "$*" ] || for A in $ARCHES; do
	[ -f "out/.repo-$A/INDEX" ] || continue
	mkdir -p "$REPO_DIR/$A"
	rsync -a --delete "out/.repo-$A/" "$REPO_DIR/$A/"
	rm -r "out/.repo-$A"
	echo "package repository: $REPO_DIR/$A ($(grep -c . "$REPO_DIR/$A/INDEX") packages)"
done
