# Telegraf metrics collection
{ config, pkgs, ... }:

{
  sops.secrets.INFLUX_TOKEN = {
    owner = "telegraf";
    group = "telegraf";
  };

  services.telegraf = {
    enable = true;

    extraConfig = {
      agent = {
        interval = "10s";
        flush_interval = "10s";
      };

      outputs.influxdb_v2 = [{
        urls = [ "https://influx.jagadam97.uk/" ];
        token = ''{{ file "${config.sops.secrets.INFLUX_TOKEN.path}" }}'';
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
