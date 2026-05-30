# Jellyfin media server
{ config, pkgs, ... }:

{
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    dataDir = "/var/lib/jellyfin";
    configDir = "/var/lib/jellyfin/config";
    cacheDir = "/var/cache/jellyfin";
    logDir = "/var/log/jellyfin";
  };

  # Use jellyfin-ffmpeg for hardware transcoding support
  environment.systemPackages = [ pkgs.jellyfin-ffmpeg ];

  # Define the tmpfs RAM disk right here next to the service
  fileSystems."/var/cache/jellyfin/transcodes" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "rw"
      "nosuid"
      "nodev"
      "noexec"
      "relatime"
      "size=10G"
      "mode=0755"
      "uid=jellyfin"
      "gid=jellyfin"
    ];
  };

  # Ensure Jellyfin doesn't start until the RAM disk filesystem is mounted
  systemd.services.jellyfin = {
    requires = [ "var-cache-jellyfin-transcodes.mount" ];
    after = [ "var-cache-jellyfin-transcodes.mount" ];
  };

  # Automatically clean up orphaned transcode chunks older than 1 hour
  systemd.tmpfiles.rules = [
    "e /var/cache/jellyfin/transcodes 0755 jellyfin jellyfin 1h -"
  ];

  # Force systemd-tmpfiles to run every 15 minutes instead of daily
  systemd.timers.systemd-tmpfiles-clean = {
    timerConfig = {
      OnBootSec = "15m";
      OnUnitActiveSec = "15m";
    };
  };

  # Ensure jellyfin can access media directories
  users.users.jellyfin.extraGroups = [
      "users"
      "video"
      "render"
    ];
}
