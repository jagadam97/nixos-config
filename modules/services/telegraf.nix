# Telegraf metrics collection.
#
# Defaults target the hosted InfluxDB the x86_64 machines use. pella overrides
# them because it writes to the LAN InfluxDB and its own bucket.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.telegrafMetrics;
in
{
  options.services.telegrafMetrics = {
    influxUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://influx.jagadam97.uk/" ];
      description = "InfluxDB v2 write endpoints.";
    };

    organization = lib.mkOption {
      type = lib.types.str;
      default = "oracle";
      description = "InfluxDB organisation.";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "officeServers";
      description = "InfluxDB bucket to write into.";
    };

    extraInputs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.attrs);
      default = { };
      example = {
        temp = [ { } ];
      };
      description = "Host-specific telegraf inputs, merged over the shared set.";
    };
  };

  config = {
    sops.secrets.INFLUX_TOKEN = {
      owner = "telegraf";
      group = "telegraf";
      # Without this, rotating the token updates the file but leaves the running
      # agent holding the old one, which looks exactly like a permissions bug.
      restartUnits = [ "telegraf.service" ];
    };
    systemd.services.telegraf.serviceConfig.EnvironmentFile = config.sops.secrets.INFLUX_TOKEN.path;

    services.telegraf = {
      enable = true;
      extraConfig = {
        agent = {
          interval = "10s";
          flush_interval = "10s";
        };

        outputs.influxdb_v2 = [{
          urls = cfg.influxUrls;
          token = "$INFLUX_TOKEN";
          organization = cfg.organization;
          bucket = cfg.bucket;
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
        } // cfg.extraInputs;
      };
    };
  };
}
