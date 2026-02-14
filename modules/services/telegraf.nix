# Telegraf metrics collection
{ config, pkgs, ... }:

{
  sops.secrets.influx_token = {
    owner = "telegraf";
    group = "telegraf";
    format = "dotenv";
    key = "INFLUX_TOKEN";
  };

  services.telegraf = {
    enable = true;
    environmentFiles = [ config.sops.secrets.influx_token.path ];

    extraConfig = {
      agent = {
        interval = "10s";
        flush_interval = "10s";
      };

      outputs.influxdb_v2 = [{
        urls = [ "https://influx.jagadam97.uk/" ];
        token = "$INFLUX_TOKEN";
        organization = "oracle";
        bucket = "officeServers";
      }];

      inputs = {
        cpu = [{ percpu = true; totalcpu = true; report_active = true; }];
        mem = [{}];
        swap = [{}];
        system = [{}];
        kernel = [{}];
        processes = [{}];
        interrupts = [{}];
        linux_sysctl_fs = [{}];
        disk = [{ ignore_fs = [ "tmpfs" "devtmpfs" "devfs" "overlay" "squashfs" ]; }];
        diskio = [{}];
        net = [{}];
        netstat = [{}];
        nstat = [{}];
        internal = [{}];
        procstat = [
          { exe = "nix-daemon"; }
          { exe = "influxd"; }
        ];
      };
    };
  };
}
