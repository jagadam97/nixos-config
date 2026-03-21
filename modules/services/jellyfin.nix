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

  # Ensure jellyfin can access media directories
  users.users.jellyfin = {
    extraGroups = [ "users" "video" "render" ];
  };
}
