# Vector - log shipping to Axiom.
#
# Two sources, both pull-based from kayda - no agent runs in the Proxmox LXCs:
#   - *arr logs are tailed off the NFS mount they already write to
#   - jellyfin is read from the local journal
#
# Only the current logfile of each app is tailed. The rotated archives
# (radarr.3.txt, bazarr.log.2026-07-25, ...) and the .debug.txt files are
# deliberately excluded - together they are >100 MB and would blow the Axiom
# ingest quota on first start.
{ config, pkgs, lib, ... }:

let
  arrRoot = "/mnt/bx500/maintainarr";

  # Both *arr and bazarr log as: <timestamp>|<level>|<logger>|<message>
  # bazarr pads level/logger with spaces and adds a trailing pipe.
  logLineRegex = ''^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?)\|(?P<level>[^|]+)\|(?P<logger>[^|]+)\|(?P<msg>[\s\S]*)$'';
in
{
  # Axiom API token. Stored raw in secrets.yaml; wrapped in an env file so
  # Vector can interpolate ${AXIOM_TOKEN} from its config.
  sops.secrets.axiom_api_key = { };
  sops.templates."axiom.env" = {
    content = "AXIOM_TOKEN=${config.sops.placeholder.axiom_api_key}";
    owner = "vector";
    group = "vector";
    mode = "0400";
  };

  # The upstream module runs Vector under DynamicUser, which cannot own a sops
  # secret. Use a fixed user instead.
  users.users.vector = {
    isSystemUser = true;
    group = "vector";
  };
  users.groups.vector = { };

  services.vector = {
    enable = true;
    journaldAccess = true;
    # The config references ${AXIOM_TOKEN}, which build-time validation cannot resolve.
    validateConfig = false;

    settings = {
      data_dir = "/var/lib/vector";

      sources = {
        jellyfin = {
          type = "journald";
          include_units = [ "jellyfin.service" ];
          current_boot_only = true;
        };

        arr = {
          type = "file";
          include = [
            "${arrRoot}/radarr/logs/radarr.txt"
            "${arrRoot}/sonarr/logs/sonarr.txt"
            "${arrRoot}/prowlarr/logs/prowlarr.txt"
            "${arrRoot}/bazarr/log/bazarr.log"
          ];
          read_from = "beginning";
          # NFS: no inotify, so Vector polls. Keep discovery cheap.
          glob_minimum_cooldown_ms = 30000;
          # .NET stack traces continue on following lines until the next timestamp.
          multiline = {
            start_pattern = ''^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'';
            condition_pattern = ''^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'';
            mode = "halt_before";
            timeout_ms = 1000;
          };
        };
      };

      transforms = {
        parse_arr = {
          type = "remap";
          inputs = [ "arr" ];
          source = ''
            # /mnt/bx500/maintainarr/<app>/... -> <app>
            .app = split(string!(.file), "/")[4]
            .host = "kayda"

            parsed, err = parse_regex(.message, r'${logLineRegex}')
            if err == null {
              .level = downcase(strip_whitespace(string!(parsed.level)))
              .logger = strip_whitespace(string!(parsed.logger))
              .message = strip_whitespace(string!(parsed.msg))
              .timestamp = parse_timestamp(string!(parsed.ts), "%Y-%m-%d %H:%M:%S%.f") ??
                           parse_timestamp(string!(parsed.ts), "%Y-%m-%d %H:%M:%S") ??
                           .timestamp
            } else {
              .level = "unknown"
            }
          '';
        };

        tag_jellyfin = {
          type = "remap";
          inputs = [ "jellyfin" ];
          source = ''
            .app = "jellyfin"
            .host = "kayda"
          '';
        };

        # Quota control: Axiom's free tier is 0.5 GB/month.
        drop_noise = {
          type = "filter";
          inputs = [ "parse_arr" "tag_jellyfin" ];
          condition = ''!includes(["debug", "trace"], .level) && (to_int(.PRIORITY) ?? 6) <= 6'';
        };
      };

      sinks.axiom = {
        type = "axiom";
        inputs = [ "drop_noise" ];
        dataset = "application-logs";
        token = "\${AXIOM_TOKEN}";
        compression = "gzip";
        batch.timeout_secs = 10;
        # Ride out Axiom/network outages without buffering in RAM.
        buffer = [{
          type = "disk";
          max_size = 268435488; # 256 MiB - the minimum Vector accepts
          when_full = "drop_newest";
        }];
      };
    };
  };

  systemd.services.vector = {
    # File source reads over NFS; don't start before the automount is usable.
    after = [ "remote-fs.target" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "vector";
      Group = "vector";
      SupplementaryGroups = lib.mkForce [ "systemd-journal" ];
      EnvironmentFile = config.sops.templates."axiom.env".path;
    };
  };
}
