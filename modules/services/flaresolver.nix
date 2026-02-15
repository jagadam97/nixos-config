# FlareSolverr for bypassing Cloudflare
{ config, lib, pkgs, ... }:

{
  services.flaresolverr = {
    enable = true;
    port = 8191;
    openFirewall = true;
  };
  
  systemd.services.flaresolverr = {
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 5;
      Environment = [
        "LOG_LEVEL=info"
        "MAX_BROWSER_INSTANCES=4"
        "TZ=Asia/kolkata"
      ];
      MemoryMax = "4G";
      MemoryHigh = "3.5G";
      CPUQuota = "400%";
    };
  };
}
