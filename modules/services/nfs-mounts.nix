# NFS mounts from storage server 192.168.4.240
# Exports: /mnt/pve/bx1000, /mnt/pve/bx500, /mnt/pve/hd4000
{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Enable NFS client support
  services.rpcbind.enable = true;
  boot.supportedFilesystems = [ "nfs" ];

  # Mount points and fstab entries
  fileSystems."/mnt/bx1000" = {
    device = "192.168.4.240:/mnt/pve/bx1000";
    fsType = "nfs";
    options = [
      "nfsvers=4"
      "soft" # don't hang forever if server goes away
      "timeo=30" # 3s timeout before retry
      "retrans=3" # retry 3 times
      "x-systemd.automount" # mount on first access
      "x-systemd.idle-timeout=600" # unmount after 10min idle
      "x-systemd.mount-timeout=30" # give up mounting after 30s
      "noatime"
      "_netdev" # wait for network before mounting
    ];
  };

  fileSystems."/mnt/bx500" = {
    device = "192.168.4.240:/mnt/pve/bx500";
    fsType = "nfs";
    options = [
      "nfsvers=4"
      "soft"
      "timeo=30"
      "retrans=3"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=30"
      "noatime"
      "_netdev"
    ];
  };

  fileSystems."/mnt/hd4000" = {
    device = "192.168.4.240:/mnt/pve/hd4000";
    fsType = "nfs";
    options = [
      "nfsvers=4"
      "soft"
      "timeo=30"
      "retrans=3"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=30"
      "noatime"
      "_netdev"
    ];
  };
}
