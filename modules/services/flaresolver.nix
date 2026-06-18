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
      # Lifecycle
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 5;

      # Environment Setup
      Environment = [
        "LOG_LEVEL=info"
        "LOG_HTML=false"
        "MAX_BROWSER_INSTANCES=2"
        "TZ=Asia/Kolkata"
        "BROWSER_TIMEOUT=90000"
      ];

      # Resource Control
      MemoryMax = "4G";
      MemoryHigh = "3.5G";
      MemorySwapMax = "0";
      CPUQuota = "400%";

      # System Hardening Sandbox
      DynamicUser = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
    };
  };
}
