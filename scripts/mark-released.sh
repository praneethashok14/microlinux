#!/bin/sh
# Remember the images in out/ as the last published release: they are copied
# to release-base/<arch>/, and the next builds make the small system update
# against them (out/update-<arch>-from-<build>.tar.zst, which goes into the
# next release next to the ISOs). Run after publishing a release.
#
#   ./scripts/mark-released.sh            every architecture in out/
#   ./scripts/mark-released.sh x86_64     one architecture
set -e
cd "$(dirname "$0")/.."
for A in ${1:-aarch64 x86_64}; do
	[ -f "out/BUILD-$A" ] || continue
	# only images that match their (published) checksums
	( cd out && grep -E "  \*?(microlinux-$A(-base)?\.iso|BUILD-$A)$" "SHA256SUMS-$A" | shasum -a 256 -c --quiet )
	mkdir -p "release-base/$A"
	for f in "microlinux-$A.iso" "microlinux-$A-base.iso" "BUILD-$A"; do
		cp "out/$f" "release-base/$A/.$f.new" && mv -f "release-base/$A/.$f.new" "release-base/$A/$f"
	done
	echo "release-base/$A: build $(cat "release-base/$A/BUILD-$A")"
done
