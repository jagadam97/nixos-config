# Hardware configuration for pella - Raspberry Pi 4 Model B Rev 1.5 (4GB)
# Board revision c03115. Bootloader EEPROM 2026/05/17, VL805 fw 000138c0.
#
# The partition layout, the FAT32 firmware partition and its contents, the boot
# loader and the kernel params all come from nixpkgs' sd-image-aarch64.nix,
# imported in ./default.nix.
#
# nixos-hardware's raspberry-pi-4 module is deliberately not used - it pins
# linuxPackages_rpi4, which is not in cache.nixos.org, so it would mean
# compiling an ARM kernel and a ZFS module under qemu emulation. We use the
# generic aarch64 kernel (cached) and add the RPi-specific initrd modules that
# nixos-hardware would have contributed by hand below.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # Grow the root partition to fill the card on first boot. This is why no
  # manual resize step is needed after writing the image.
  sdImage.expandOnBoot = true;

  # Uncompressed image so it can be dd'd straight to the card; the default zstd
  # image would have to be decompressed first.
  sdImage.compressImage = false;

  # mmc_block for the internal microSD; the usb/xhci set so a USB-attached root
  # stays possible without an initrd rebuild (a USB SSD is the intended
  # long-term medium for this host).
  # mmc_block for the internal microSD. pcie-brcmstb and reset-raspberrypi are
  # what nixos-hardware's raspberry-pi-4 module contributes and they matter
  # here: the VL805 USB3 controller hangs off PCIe, so without them the USB
  # NIC (phase 2's WAN) and any USB-attached root would not come up.
  boot.initrd.availableKernelModules = [
    "mmc_block"
    "pcie-brcmstb"
    "reset-raspberrypi"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "uas"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];

  # sd-image-aarch64 imports nixos/modules/profiles/base.nix, which enables
  # btrfs, cifs, f2fs, ntfs, xfs and zfs. This host needs exactly two: ext4 for
  # the root and vfat for the firmware partition.
  #
  # zfs is the one that actually matters. It is an out-of-tree kernel module
  # pinned to the exact kernel version, so leaving it in means a zfs/kernel
  # version mismatch can block a nixos-rebuild - on the machine that will be
  # carrying the household internet. The rest are just closure weight.
  boot.supportedFilesystems = {
    zfs = lib.mkForce false;
    btrfs = lib.mkForce false;
    cifs = lib.mkForce false;
    f2fs = lib.mkForce false;
    ntfs = lib.mkForce false;
    xfs = lib.mkForce false;
  };

  # 4GB board that will be running nixos-rebuild. Debian ran 2GB of zram here,
  # which is worth keeping.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  hardware.enableRedistributableFirmware = true;
}
