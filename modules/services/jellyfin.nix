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

  # Ensure jellyfin can access media directories
  users.users.jellyfin = {
    extraGroups = [
      "users"
      "video"
      "render"
    ];
  };
}
