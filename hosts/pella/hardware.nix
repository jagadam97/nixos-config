# Hardware configuration for pella - Raspberry Pi 4 Model B Rev 1.5 (4GB)
# Board revision c03115. Bootloader EEPROM 2026/05/17, VL805 fw 000138c0.
#
# The boot loader itself (grub off, generic-extlinux-compatible on), the RPi4
# kernel and the device-tree filter all come from nixos-hardware's
# raspberry-pi-4 module, wired in flake.nix. Firmware partition contents come
# from ./firmware.nix.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  nixpkgs.hostPlatform = "aarch64-linux";

  # Build the disk image on x86_64 using binfmt for the aarch64 userland. The
  # build VM runs an x86_64 kernel, so this is not a fully emulated ARM VM -
  # only userland instructions go through qemu. Both remote builders (alienX,
  # nauvoo) are x86_64 with qemu-aarch64 registered.
  disko.imageBuilder = {
    enableBinfmt = true;
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    kernelPackages = inputs.nixpkgs.legacyPackages.x86_64-linux.linuxPackages_latest;
  };

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
  boot.supportedFilesystems = [
    "btrfs"
    "vfat"
    "ext4"
  ];

  # HDMI console only. The upstream sd-image also sets ttyS0/ttyAMA0 for boards
  # with serial headers; this Pi is managed over the network and Debian ran with
  # 8250.nr_uarts=0 anyway.
  boot.kernelParams = [ "console=tty1" ];

  # Disko owns fileSystems - see ./disko.nix
  swapDevices = [ ];

  # 4GB board that will be running nixos-rebuild. Debian ran 2GB of zram here,
  # which is worth keeping.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  hardware.enableRedistributableFirmware = true;
}
