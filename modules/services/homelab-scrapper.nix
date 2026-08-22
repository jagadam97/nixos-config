# Homelab qBittorrent metrics scraper.
#
# The package comes from the app's own flake; this module owns the NixOS side
# only - a system user, the environment file holding its credentials, and a
# hardened unit. Disabled until hosts/pella/default.nix points environmentFile
# at a sops secret.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.homelabScrapper;
in
{
  options.services.homelabScrapper = {
    enable = lib.mkEnableOption "the homelab qBittorrent metrics scraper";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.homelab-scrapper.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.homelab-scrapper.packages.\${system}.default";
      description = "Scraper package to run.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      example = "/run/secrets/homelab-scrapper.env";
      description = ''
        File holding QBIT_URL, QBIT_API_KEY, INFLUX_URL, INFLUX_TOKEN,
        INFLUX_ORG, INFLUX_BUCKET and SCRAPE_INTERVAL, one KEY=value per line.
        Must be readable by the homelab-scrapper user, so point it at a sops
        secret with that owner.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.homelab-scrapper = {
      isSystemUser = true;
      group = "homelab-scrapper";
      description = "homelab-scrapper service user";
    };
    users.groups.homelab-scrapper = { };

    systemd.services.homelab-scrapper = {
      description = "Homelab qBittorrent metrics scraper";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        EnvironmentFile = cfg.environmentFile;
        Restart = "on-failure";
        RestartSec = "5s";
        User = "homelab-scrapper";
        Group = "homelab-scrapper";

        # Outbound connections to qBittorrent and InfluxDB are all it needs.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
