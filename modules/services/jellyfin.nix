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

  # Automatically wipe out cached transcode chunks older than 4 hours
  systemd.tmpfiles.rules = [
    "d /var/cache/jellyfin/transcodes 0700 jellyfin jellyfin 4h"
  ];

  # Ensure jellyfin can access media directories
  users.users.jellyfin = {
    extraGroups = [
      "users"
      "video"
      "render"
    ];
  };
}
