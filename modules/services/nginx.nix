{ config, pkgs, ... }:

{
  services.nginx = {
    enable = true;

    # The 'stream' block is used for TCP/UDP proxying
    streamConfig = ''
      upstream backend_9092 {
          server 10.10.71.83:22;
      }

      upstream backend_9093 {
          server 10.10.71.83:8080;
      }

      server {
          listen 8111;
          proxy_pass backend_9092;
      }

      server {
          listen 8112;
          proxy_pass backend_9093;
      }
    '';
  };
}
