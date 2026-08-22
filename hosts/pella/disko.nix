# Disk layout for pella - internal microSD (/dev/mmcblk0, 29.8GB Samsung EB1QT)
#
# Three partitions, unlike the two used on the x86 hosts:
#   p1  /boot/firmware  FAT32  RPi firmware blobs + u-boot, read by the SoC
#   p2  /boot           ext4   extlinux.conf + kernels, read by u-boot
#   p3  /               btrfs  subvolumes
#
# /boot is a separate ext4 partition on purpose. u-boot has to read
# extlinux.conf, and its btrfs support is read-only and unreliable with
# subvolumes - putting /boot on btrfs risks a Pi that does not boot at all.
{ ... }:

let
  # zstd:3 rather than the x86 hosts' zstd:6 - four Cortex-A72 cores will be
  # competing with PPPoE softirq load once this box is the router.
  # No "ssd": that is an allocation hint for real SSDs, meaningless on microSD.
  # discard=async: the card reports discard_granularity=4194304 and
  # discard_max_bytes=170519429120, and async keeps trims off the write path
  # (synchronous discard can stall writes badly on SD).
  btrfsMountOptions = [
    "compress=zstd:3"
    "noatime"
    "discard=async"
  ];
in
{
  disko.devices = {
    disk = {
      sd = {
        type = "disk";
        device = "/dev/mmcblk0";

        # Image build settings. disko has no auto-resize, so this size is what
        # you get until btrfs is grown to fill the real card after first boot.
        # Keep it well under the card's 29.8G: build, transfer and dd time all
        # scale with it.
        imageName = "pella-aarch64-rpi4";
        imageSize = "12G";

        content = {
          type = "gpt";
          partitions = {
            # priority is load-bearing: without it disko orders partitions by
            # attribute name alphabetically, which would put "boot" before
            # "firmware" and hand the SoC the wrong first partition.
            firmware = {
              priority = 1;
              size = "512M";
              type = "0700";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            boot = {
              priority = 2;
              size = "1G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            root = {
              priority = 3;
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = btrfsMountOptions;
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = btrfsMountOptions;
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = btrfsMountOptions;
                  };
                  "@varlib" = {
                    mountpoint = "/var/lib";
                    mountOptions = btrfsMountOptions;
                  };
                  "@log" = {
                    mountpoint = "/var/log";
                    mountOptions = btrfsMountOptions;
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
