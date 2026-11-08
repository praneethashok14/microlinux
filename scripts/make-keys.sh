#!/bin/sh
# Create the MicroLinux signing keys (once). Run inside the build VM (needs
# openssl and gpg):  limactl shell builder ./scripts/make-keys.sh
#
#   keys/                         PRIVATE - git-ignored, never publish, back it up
#     secureboot/MOK.key, MOK.crt   signs GRUB and the kernel (Secure Boot via shim)
#     repo/repo.key                 signs the package repository INDEX
#     gpg/                          GnuPG home: signs SHA256SUMS of the ISOs
#   external/board/microlinux/keys/   PUBLIC - committed, built into the system
#     MOK.cer                       certificate to enroll in MOK Manager (DER)
#     repo.pub                      mlpkg verifies INDEX.sig with it
#     microlinux-release.asc        GPG public key for SHA256SUMS.asc
#
# Existing keys are never overwritten.
set -e
cd "$(dirname "$0")/.."
K=keys
PUB=external/board/microlinux/keys
mkdir -p "$K/secureboot" "$K/repo" "$K/gpg" "$PUB"
chmod 700 "$K" "$K/gpg"

if [ ! -f "$K/secureboot/MOK.key" ]; then
	openssl req -new -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -quiet \
		-subj "/CN=MicroLinux Secure Boot Signing Key/" \
		-addext "extendedKeyUsage=codeSigning" \
		-keyout "$K/secureboot/MOK.key" -out "$K/secureboot/MOK.crt"
	echo "created Secure Boot key"
fi
openssl x509 -in "$K/secureboot/MOK.crt" -outform DER -out "$PUB/MOK.cer"

if [ ! -f "$K/repo/repo.key" ]; then
	openssl ecparam -name prime256v1 -genkey -noout -out "$K/repo/repo.key"
	echo "created repository key"
fi
openssl ec -in "$K/repo/repo.key" -pubout -out "$PUB/repo.pub" 2>/dev/null

export GNUPGHOME="$PWD/$K/gpg"
if ! gpg --batch --list-secret-keys 2>/dev/null | grep -q sec; then
	gpg --batch --quiet --passphrase '' --quick-generate-key \
		"MicroLinux Release Signing <127429640+praneethashok14@users.noreply.github.com>" ed25519 sign 10y
	echo "created GPG release key"
fi
gpg --batch --armor --export > "$PUB/microlinux-release.asc"
chmod -R go-rwx "$K"
echo "public keys in $PUB:"; ls -l "$PUB"
gpg --batch --fingerprint 2>/dev/null | sed -n '/^pub/,/^uid/p'
