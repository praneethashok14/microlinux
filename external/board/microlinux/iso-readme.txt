MicroLinux @VERSION@ - a tiny, fully functional Linux distribution (@ARCH@).

Boot: @BOOT@
      Write this image to a USB stick with
      dd if=microlinux-@ARCH@.iso of=/dev/sdX bs=4M conv=fsync
      or boot it as a CD/ISO in a VM.

Live session users:  user / live      root / microlinux
Install to disk:     sudo ml-install /dev/<disk>
Packages:            mlpkg list | mlpkg install <name>
