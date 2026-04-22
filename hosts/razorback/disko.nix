# Disk layout for razorback - nvme0n1
# GPT + EFI + btrfs with subvolumes
# NOTE: Verify device path matches your hardware (lsblk)
{ ... }:

{
  disko.devices = {
    disk = {
      nvme = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "fmask=0077" "dmask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd:6" "noatime" "ssd" ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd:6" "noatime" "ssd" ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd:6" "noatime" "ssd" ];
                  };
                  "@varlib" = {
                    mountpoint = "/var/lib";
                    mountOptions = [ "compress=zstd:6" "noatime" "ssd" ];
                  };
                  "@log" = {
                    mountpoint = "/var/log";
                    mountOptions = [ "compress=zstd:6" "noatime" "ssd" ];
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
