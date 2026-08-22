# Hardware configuration for pella - Raspberry Pi 4 Model B Rev 1.5 (4GB)
# Board revision c03115. Bootloader EEPROM 2026/05/17, VL805 fw 000138c0.
#
# The boot loader (grub off, generic-extlinux-compatible on), the RPi4 kernel
# and the device-tree filter come from nixos-hardware's raspberry-pi-4 module.
# The partition layout, the FAT32 firmware partition and its contents all come
# from nixpkgs' sd-image-aarch64.nix, imported in ./default.nix.
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
  boot.initrd.availableKernelModules = [
    "mmc_block"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "uas"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];

  # 4GB board that will be running nixos-rebuild. Debian ran 2GB of zram here,
  # which is worth keeping.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  hardware.enableRedistributableFirmware = true;
}
