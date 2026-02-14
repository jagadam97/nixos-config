{ config, pkgs, ... }:

{
  services.nginx = {
    enable = true;

    # The 'stream' block is used for TCP/UDP proxying
    streamConfig = ''
      upstream backend_9092 {
          server 127.0.0.1:9092;
      }

      upstream backend_9093 {
          server 127.0.0.1:9093;
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
