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
    "hard" # retry forever rather than going read-only on timeout
    "timeo=600" # 60s timeout before retry (10x longer than soft)
    "retrans=5" # retry 5 times before returning an error
    "noatime"
    "_netdev"
    "x-systemd.automount"
    "x-systemd.mount-timeout=60"
  ];
in
{
  # Enable NFS client support
  services.rpcbind.enable = true;
  boot.supportedFilesystems = [ "nfs" ];

  fileSystems."/mnt/bx1000" = {
    device = "192.168.4.240:/mnt/pve/bx1000";
    fsType = "nfs";
    options = commonOpts ++ [ "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/bx500" = {
    device = "192.168.4.240:/mnt/pve/bx500";
    fsType = "nfs";
    options = commonOpts ++ [ "x-systemd.idle-timeout=600" ];
  };

  # hd4000 is the active media/encoding drive - no idle timeout
  fileSystems."/mnt/hd4000" = {
    device = "192.168.4.240:/mnt/pve/hd4000";
    fsType = "nfs";
    options = commonOpts;
  };
}
