# Secure Boot and signatures

MicroLinux signs three things. The private keys are made once with
`scripts/make-keys.sh` and live in `keys/` (git-ignored, never published);
the public halves are in `external/board/microlinux/keys/` and in the system
under `/usr/share/microlinux/keys/`.

| What | Signed with | Checked by |
|------|-------------|------------|
| GRUB and the kernel (x86_64) | `keys/secureboot/MOK.key` (RSA 2048, X.509 `MOK.crt`) | shim, with UEFI Secure Boot on |
| Package repository `INDEX` | `keys/repo/repo.key` (EC P-256) | `mlpkg update` (`INDEX.sig`, `repo.pub`) |
| ISO checksums `SHA256SUMS-<arch>` | GPG key `631C AB88 0479 90B7 59C8 3CA7 B586 637D 51F2 DF89` | you, before writing an ISO to a stick |

## Secure Boot (x86_64)

The boot chain on the ISO and on installed systems:

```
UEFI firmware (Microsoft keys)
  └─ EFI/BOOT/BOOTX64.EFI   shim 16.1, signed by Microsoft (Debian 13 shim-signed)
       └─ grubx64.efi       GRUB 2.12, SBAT grub,5, signed with the MicroLinux key
            └─ /boot/vmlinuz   Linux, signed with the MicroLinux key (checked through shim)
```

Microsoft only signs shim. MicroLinux's own key has to be enrolled once per
computer, with MOK Manager (`mmx64.efi`, also on the medium). Nothing has to be
switched off.

### First boot with Secure Boot on

1. Boot the stick. A blue screen says **"Verification failed: (0x1A) Security
   Violation"**: shim doesn't know the MicroLinux key yet. Press **Enter** (OK).
2. **Shim UEFI key management** opens. Press a key within 10 seconds.
3. Choose **Enroll key from disk**, select the stick (the small EFI volume),
   then the file **`ENROLL_THIS_KEY_IN_MOK_MANAGER.cer`**.
4. **View key 0** shows "MicroLinux Secure Boot Signing Key": check it, then
   **Continue** → **Yes**, and **Reboot**.

From then on MicroLinux boots with Secure Boot on, from the stick and after
`ml-install` (the installer copies shim, GRUB, MOK Manager and the certificate
to the disk). To remove the key later: `mokutil --delete` from any Linux, or
MOK Manager's **Delete key**.

The GRUB SBAT generation is 5 because Buildroot's GRUB 2.12 carries the
February 2025 security fixes (`boot/grub2/*.patch`: CVE-2024-45774… and
CVE-2025-0622…). Shim 16.1 refuses anything below that.

aarch64 images aren't Secure-Boot signed (arm64 PCs with Secure Boot are
rare); they boot with Secure Boot off.

### Testing

`tests/.run/secboot/sbtest.py` boots the ISO in QEMU with Debian's
`OVMF_CODE_4M.secboot.fd` and Microsoft keys (`OVMF_VARS_4M.ms.fd`):
`nokey` must stop at shim's "Verification failed", `mok` (key in MokList,
made with `virt-fw-vars --add-mok`) must boot with `SecureBoot=1`.

## Signed package repository

`mlpkg update` downloads `INDEX.sig` with every online repository's `INDEX`
and checks it with `/usr/share/microlinux/keys/repo.pub`. A repository whose
signature is missing or wrong is not used. Because every package is checked
against the SHA-256 in the signed INDEX, a package can't be swapped either.
Your own unsigned repository: `sudo mlpkg repo add URL unsigned`.

## Verifying a downloaded ISO

```sh
gpg --import microlinux-release.asc          # once (external/board/microlinux/keys/)
gpg --verify SHA256SUMS-x86_64.asc SHA256SUMS-x86_64
sha256sum -c SHA256SUMS-x86_64               # macOS: shasum -a 256 -c SHA256SUMS-x86_64
```

`gpg` must report a good signature from "MicroLinux Release Signing" with the
fingerprint above.

## Keys

Back up `keys/`. Losing `MOK.key` means a new key that every computer has to
enroll again; losing `repo.key` means installed systems need a new `repo.pub`
(a system update) before they accept the repository again.
