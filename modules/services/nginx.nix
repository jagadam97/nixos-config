{ config, pkgs, ... }:

{
  services.nginx = {
    enable = true;

    # The 'stream' block is used for TCP/UDP proxying
    streamConfig = ''
      upstream backend_alienx {
          server 10.10.69.242:22;
      }

      upstream backend_tail_alienx {
          server 100.121.203.82:22;
      }

      upstream backend_incus {
          server 10.10.71.176:22;
      }


      server {
          listen 8111;
          proxy_pass backend_alienx;
      }

      server {
          listen 8112;
          proxy_pass backend_incus;
      }

      server {
          listen 8113;
          proxy_pass backend_tail_alienx;
      }
    '';
  };
}
