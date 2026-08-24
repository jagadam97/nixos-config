# openGym (gitlab.com/DuarteSantos8/opengym) - self-hosted gym and body-weight
# tracker, built from source rather than run from upstream's container images.
#
# Upstream ships a three-service compose file: an alpine/git job that downloads
# the exercise media, a Node API, and an nginx image that both serves the built
# React app and proxies /api to the API so everything sits on one origin. None
# of that needs a container runtime here:
#
#   media -> a systemd oneshot with git, into /var/lib/opengym/media
#   api   -> buildNpmPackage + a plain unit on ${apiPort}
#   web   -> static-web-server on ${webPort}, serving the vite dist
#
# The single-origin part is deliberately NOT done on this host: the reverse
# proxy in front routes / to the web port and /api/ to the API port, so the
# browser still sees one origin. That is what passkeys actually check.
#
# Which means rpId and origin below have to name *the proxy's* hostname, not
# this box. Get them wrong and registration fails with a mismatched-origin
# error rather than anything obviously DNS-shaped.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  cfg = config.services.opengym;

  version = "1.2.9";
  src = inputs.opengym;

  # The React app. Nothing arch-specific survives into dist/ - it is the
  # bundled JS/CSS/HTML - but the *build* runs esbuild and rollup, which are
  # native binaries. On kayda this happens under binfmt aarch64 emulation.
  # Upstream's Dockerfile pins this stage to the build platform for exactly
  # that reason; here the lockfile decides which optional native packages get
  # fetched, so the emulated build gets the aarch64 binaries it expects rather
  # than npm guessing wrong under QEMU.
  frontend = pkgs.buildNpmPackage {
    pname = "opengym-frontend";
    inherit version;
    src = "${src}/frontend";
    npmDepsHash = "sha256-FogLxlDIAJuMcY4fb+4p/DCrxIK7VMKPZrdZfAM+xTw=";

    # sharp arrives via @capacitor/assets and its postinstall wants to write
    # _libvips into the npm cache - a read-only store path - and then fetch a
    # prebuilt libvips off the network, which the sandbox has no route to. It
    # is a mobile-asset tool; `vite build` never touches it. esbuild and rollup
    # do not need their scripts either: npm resolves their native halves as
    # per-platform packages straight from the lockfile.
    npmFlags = [ "--ignore-scripts" ];

    # vite build only. The capacitor mobile targets and vitest come along as
    # devDependencies because the lockfile has them; none of them run here.
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

  # Node, no framework: two dependencies and a single server.js.
  api = pkgs.buildNpmPackage {
    pname = "opengym-api";
    inherit version;
    src = "${src}/api";
    npmDepsHash = "sha256-KrJW6aaM5uzMZ7O1nJ7XVCnp4Da/qzX1r/1h8ojaQRM=";

    # There is no build script - package.json only has `start`.
    dontNpmBuild = true;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/opengym-api
      cp -r node_modules server.js package.json $out/lib/opengym-api/
      makeWrapper ${lib.getExe pkgs.nodejs_22} $out/bin/opengym-api \
        --add-flags $out/lib/opengym-api/server.js
      runHook postInstall
    '';
  };

  dataDir = "/var/lib/opengym";
  mediaDir = "${dataDir}/media";
  wwwDir = "${dataDir}/www";

  # ~140 MB of exercise images and GIFs. Fetched at runtime rather than pinned
  # into the store on purpose: it is third-party media under Gym visual's terms
  # (see upstream NOTICE.md), it never changes, and putting it in the closure
  # would mean copying it to this host on every single deploy.
  mediaScript = pkgs.writeShellScript "opengym-fetch-media" ''
    set -euo pipefail

    if [ -n "$(ls -A ${mediaDir}/img 2>/dev/null)" ]; then
      echo "[opengym] exercise media already present, skipping download"
      exit 0
    fi

    echo "[opengym] downloading exercise media (~140 MB, one time)"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    ${pkgs.git}/bin/git clone --depth 1 \
      https://github.com/hasaneyldrm/exercises-dataset "$TMP/ds"

    cp "$TMP"/ds/images/*.jpg ${mediaDir}/img/
    cp "$TMP"/ds/videos/*.gif ${mediaDir}/gif/

    echo "[opengym] media ready ($(ls ${mediaDir}/img | wc -l) images)"
  '';

  # static-web-server needs one directory holding both the built app and the
  # media, and the built app is a read-only store path. Symlinks rather than a
  # copy: SWS follows them (it only stops if --disable-symlinks is set), and
  # the store path changes on every upgrade, so anything copied would go stale.
  linkWwwScript = pkgs.writeShellScript "opengym-link-www" ''
    set -euo pipefail
    rm -rf ${wwwDir}
    mkdir -p ${wwwDir}
    for f in ${frontend}/*; do
      ln -sfn "$f" ${wwwDir}/
    done
    ln -sfn ${mediaDir}/img ${wwwDir}/img
    ln -sfn ${mediaDir}/gif ${wwwDir}/gif
  '';

  swsConfig = (pkgs.formats.toml { }).generate "opengym-sws.toml" {
    general = {
      host = "0.0.0.0";
      port = cfg.webPort;
      root = wwwDir;
      log-level = "info";
      directory-listing = false;
      # react-router owns the URL space; anything that is not a real file has
      # to come back as the app shell, not a 404.
      page-fallback = "${wwwDir}/index.html";
      compression = true;
      cache-control-headers = true;
    };
  };
in
{
  options.services.opengym = {
    enable = lib.mkEnableOption "openGym";

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Port serving the built frontend. Proxy `/` here.";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port the Node API listens on. Proxy `/api/` here.";
    };

    rpId = lib.mkOption {
      type = lib.types.str;
      example = "gym.example.com";
      description = ''
        The hostname passkeys are bound to - the one in the browser's address
        bar, i.e. your reverse proxy's name, not this host's. Bare hostname, no
        scheme, no port.
      '';
    };

    origin = lib.mkOption {
      type = lib.types.str;
      example = "https://gym.example.com";
      description = ''
        The full URL the app is served from, as the browser sees it. Must match
        the proxy exactly, scheme included. Browsers refuse passkeys outside a
        secure context, so in practice this is https:// (localhost aside).
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        ADMIN_UIDS = "abc123";
        INVITE_ONLY = "1";
        ALLOW_GUEST = "0";
      };
      description = ''
        Extra environment for the API, passed through as-is. See upstream's
        .env.example: ADMIN_UIDS, INVITE_ONLY, ALLOW_GUEST, SESSION_DAYS,
        AUDIT_LOG, AUDIT_MAX, AUDIT_DAYS, AUDIT_IP, VAPID_SUBJECT.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open both ports. Needed because the proxy runs on another host - if it
        ran here, neither port would have to leave loopback.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.opengym = {
      isSystemUser = true;
      group = "opengym";
      home = dataDir;
    };
    users.groups.opengym = { };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 opengym opengym -"
      # Profiles, passkeys, per-user state, the session secret and vapid.json.
      # This directory is the entire backup.
      "d ${dataDir}/data 0750 opengym opengym -"
      "d ${mediaDir} 0755 opengym opengym -"
      "d ${mediaDir}/img 0755 opengym opengym -"
      "d ${mediaDir}/gif 0755 opengym opengym -"
    ];

    systemd.services.opengym-media = {
      description = "Download openGym exercise media";
      wantedBy = [ "multi-user.target" ];
      before = [ "opengym-web.service" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "opengym";
        Group = "opengym";
        ExecStart = mediaScript;
        # A 140 MB clone onto a microSD, once.
        TimeoutStartSec = "30min";
      };
    };

    systemd.services.opengym-api = {
      description = "openGym API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        PORT = toString cfg.apiPort;
        DATA_DIR = "${dataDir}/data";
        RP_ID = cfg.rpId;
        ORIGIN = cfg.origin;
        RP_NAME = "openGym";
        NODE_ENV = "production";
      }
      // cfg.settings;

      serviceConfig = {
        Type = "simple";
        User = "opengym";
        Group = "opengym";
        ExecStart = "${api}/bin/opengym-api";
        Restart = "on-failure";
        RestartSec = 5;

        ProtectSystem = "strict";
        ReadWritePaths = [ "${dataDir}/data" ];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    systemd.services.opengym-web = {
      description = "openGym web (static-web-server)";
      wantedBy = [ "multi-user.target" ];
      after = [ "opengym-media.service" ];

      serviceConfig = {
        Type = "simple";
        User = "opengym";
        Group = "opengym";
        # Rebuilt on every start so an upgrade's new dist path is picked up
        # without leaving the previous one linked.
        ExecStartPre = linkWwwScript;
        ExecStart = "${lib.getExe pkgs.static-web-server} --config-file ${swsConfig}";
        Restart = "on-failure";
        RestartSec = 5;

        ProtectSystem = "strict";
        ReadWritePaths = [ wwwDir ];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.webPort
      cfg.apiPort
    ];
  };
}
