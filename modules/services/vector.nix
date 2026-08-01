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
  # Axiom API token, read through Vector's own secrets backend.
  #
  # Do NOT switch this to a "${AXIOM_TOKEN}" env var: Vector 0.57 does not
  # interpolate env vars into sink options, and rather than failing it ships
  # the literal string as the bearer token, which Axiom rejects with
  # {"code":401,"message":"token not supported"}.
  sops.secrets.axiom_api_key = {
    owner = "vector";
    group = "vector";
    mode = "0400";
  };

  # The upstream module runs Vector under DynamicUser, which cannot own a sops
  # secret. Use a fixed user instead. The keys group grants access to /run/secrets.
  users.users.vector = {
    isSystemUser = true;
    group = "vector";
    extraGroups = [ "keys" ];
  };
  users.groups.vector = { };

  services.vector = {
    enable = true;
    journaldAccess = true;
    # Validation would try to resolve SECRET[...] against /run/secrets, which
    # does not exist in the build sandbox.
    validateConfig = false;

    settings = {
      data_dir = "/var/lib/vector";

      # Resolves SECRET[sops.<key>] placeholders against sops-nix's output dir.
      secret.sops = {
        type = "directory";
        path = "/run/secrets";
      };

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
        token = "SECRET[sops.axiom_api_key]";
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
      SupplementaryGroups = lib.mkForce [ "systemd-journal" "keys" ];
    };
  };
}
