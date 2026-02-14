# FlareSolverr for bypassing Cloudflare
{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:latest";
    autoStart = true;
    environment = {
      "LOG_LEVEL" = "info";
      "TZ" = "Asia/Kolkata";
    };
    ports = [ "8191:8191" ];
  };
}
