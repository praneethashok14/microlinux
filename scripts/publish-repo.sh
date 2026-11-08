#!/bin/sh
# Publish the package repository in ../microlinux-repo (REPO_DIR) to GitHub:
# the packages of each architecture become the assets of release
# packages-<arch>, and the folder itself (README, INDEX, SOURCES.txt) is
# committed and pushed. MicroLinux finds the releases through the URL in
# external/board/microlinux/repo-url.
#
#   ./scripts/publish-repo.sh             every architecture that has been built
#   ./scripts/publish-repo.sh x86_64      one architecture
#
# Needs the GitHub CLI, logged in (gh auth login), or a token for the account
# in GH_TOKEN (used for this run only, never stored). Packages that are already
# uploaded are skipped (file names contain the version), packages no longer
# in the INDEX are deleted, and the INDEX is uploaded last, so a client never
# sees an INDEX that names a file which isn't there yet.
set -e
cd "$(dirname "$0")/.."
REPO_DIR=${REPO_DIR:-$(cd .. && pwd)/microlinux-repo}
GH_REPO=$(sed -n 's|^https://github.com/\([^/]*/[^/]*\)/releases/download/.*|\1|p' external/board/microlinux/repo-url)
[ -n "$GH_REPO" ] || { echo "no GitHub URL in external/board/microlinux/repo-url"; exit 1; }
export GH_REPO
ARCHES=${1:-$(for a in aarch64 x86_64; do [ -f "$REPO_DIR/$a/INDEX" ] && echo $a; done)}
[ -n "$ARCHES" ] || { echo "nothing to publish: build first (./scripts/build.sh)"; exit 1; }

if ! gh repo view "$GH_REPO" >/dev/null 2>&1; then
	echo "creating public repository $GH_REPO"
	gh repo create "$GH_REPO" --public \
		--description "MicroLinux package repository (mlpkg): software built from source with Buildroot for aarch64 and x86_64. OS: github.com/praneethashok14/microlinux"
fi
# the folder itself: README, INDEX and SOURCES.txt per architecture (packages are git-ignored)
git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1 || git -C "$REPO_DIR" remote add origin "https://github.com/$GH_REPO.git"
git -C "$REPO_DIR" add -A
git -C "$REPO_DIR" diff --cached --quiet || git -C "$REPO_DIR" commit -q -m "Update package lists: $ARCHES"
if [ -n "$GH_TOKEN" ]; then
	# authenticate this push with GH_TOKEN instead of any stored credential
	git -C "$REPO_DIR" -c credential.helper= \
		-c 'credential.helper=!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f' \
		push -q -u origin main
else
	git -C "$REPO_DIR" push -q -u origin main
fi

for A in $ARCHES; do
	D=$REPO_DIR/$A
	[ -f "$D/INDEX" ] || { echo "$D/INDEX missing"; exit 1; }
	TAG=packages-$A
	gh release view "$TAG" >/dev/null 2>&1 || gh release create "$TAG" --title "MicroLinux packages ($A)" \
		--notes "mlpkg repository for MicroLinux $A. On MicroLinux: \`sudo mlpkg update\`, \`mlpkg list\`, \`sudo mlpkg install <name>\`. Every package's SHA-256 is in INDEX. Package sources: see SOURCES.txt."
	have=$(gh release view "$TAG" --json assets -q '.assets[].name')
	n=0
	for f in $(cut -d'|' -f3 "$D/INDEX"); do
		echo "$have" | grep -qxF "$f" && continue
		gh release upload "$TAG" "$D/$f"
		n=$((n + 1))
	done
	[ -f "$D/SOURCES.txt" ] && gh release upload "$TAG" "$D/SOURCES.txt" --clobber
	gh release upload "$TAG" "$D/INDEX" --clobber
	# assets that the new INDEX no longer names
	for f in $have; do
		case "$f" in INDEX|SOURCES.txt) continue ;; esac
		cut -d'|' -f3 "$D/INDEX" | grep -qxF "$f" || gh release delete-asset "$TAG" "$f" -y
	done
	echo "$A: $(grep -c . "$D/INDEX") packages ($n uploaded) -> https://github.com/$GH_REPO/releases/tag/$TAG"
done
