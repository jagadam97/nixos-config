# NFS mounts from storage server 192.168.4.240
# Exports: /mnt/pve/bx1000, /mnt/pve/bx500, /mnt/pve/hd4000
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # hard mount so writes never silently fail with read-only errors under load
  # idle-timeout disabled on hd4000 since it's used for active video encoding
  commonOpts = [
    "nfsvers=4"
    "hard"
    "timeo=150" # Reduced to 15s to fail/retry faster
    "retrans=5"
    "intr" # Allow interruption - helps with shutdown/reboot
    "noatime"
    "_netdev"
    "x-systemd.automount"
    "x-systemd.mount-timeout=10" # How long systemd waits to give up on the mount
  ];
in
{
  # Enable NFS client support
  services.rpcbind.enable = true;
  boot.supportedFilesystems = [ "nfs" ];

  fileSystems."/mnt/bx1000" = {
    device = "192.168.4.240:/mnt/pve/bx1000";
    fsType = "nfs";
    options = commonOpts;
  };

  fileSystems."/mnt/bx500" = {
    device = "192.168.4.240:/mnt/pve/bx500";
    fsType = "nfs";
    options = commonOpts;
  };

  # hd4000 is the active media/encoding drive - no idle timeout
  fileSystems."/mnt/hd4000" = {
    device = "192.168.4.240:/mnt/pve/hd4000";
    fsType = "nfs";
    options = commonOpts;
  };
}
