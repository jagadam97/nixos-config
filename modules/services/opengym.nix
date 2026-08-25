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

  # Local scratch: the built app and the downloaded media. Neither is worth
  # backing up - both are reproducible from the store and from upstream.
  stateDir = "/var/lib/opengym";
  mediaDir = "${stateDir}/media";
  wwwDir = "${stateDir}/www";

  # The part that actually matters, and the only thing to back up.
  dataDir = cfg.dataDir;

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
  # Clears the *contents* rather than the directory. ProtectSystem=strict gives
  # this unit exactly one writable path - wwwDir itself - so removing wwwDir
  # would need write access to its parent, which it does not have. tmpfiles
  # owns the directory's existence, and it has to exist before the unit starts
  # at all: systemd cannot bind a missing ReadWritePaths entry into the mount
  # namespace, and fails the unit with 226/NAMESPACE before ExecStartPre runs.
  linkWwwScript = pkgs.writeShellScript "opengym-link-www" ''
    set -euo pipefail
    find ${wwwDir} -mindepth 1 -delete
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

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/opengym/data";
      example = "/mnt/bx500/opengym/data";
      description = ''
        Where profiles, passkeys, per-user state, the session secret and
        vapid.json live. Back up this directory and you have backed up openGym.

        Putting it on an NFS mount keeps it off the SD card and inside an
        existing backup, at the cost of a hard dependency: the unit gains a
        RequiresMountsFor on this path, so it waits for the mount and refuses to
        start without it rather than quietly writing to an empty directory.
        Ownership is then the export's business - if the server squashes or
        remaps the opengym uid, the API fails on its first write.
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
    # uid/gid are pinned because dataDir can live on NFS, and an NFSv4 sec=sys
    # export authorises by numeric id. An auto-allocated uid would drift the
    # first time the user is recreated - which rollbacks do - and the server
    # would then refuse writes to a directory it still believes is owned by
    # somebody else. 995/992 are what this host allocated; keep them in step
    # with whatever owns the directory on the NAS.
    users.users.opengym = {
      isSystemUser = true;
      group = "opengym";
      uid = 995;
      home = stateDir;
    };
    users.groups.opengym.gid = 992;

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 opengym opengym -"
      "d ${mediaDir} 0755 opengym opengym -"
      "d ${mediaDir}/img 0755 opengym opengym -"
      "d ${mediaDir}/gif 0755 opengym opengym -"
    ];

    # tmpfiles cannot own dataDir once it lives on NFS: it runs early, before
    # the automount has anything behind it, and a `d` rule that lands on the
    # bare mountpoint is worse than useless. This runs as root, after the mount,
    # immediately before the API - and it is the unit that will say plainly
    # whether the export lets root create a directory at all.
    #
    # It has no namespace hardening on purpose. ReadWritePaths on a path that
    # does not exist yet is what failed the API with 226/NAMESPACE; something
    # unconfined has to create it first.
    systemd.services.opengym-data-init = {
      description = "Prepare openGym data directory";
      wantedBy = [ "multi-user.target" ];
      before = [ "opengym-api.service" ];
      unitConfig.RequiresMountsFor = [ dataDir ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "opengym-data-init" ''
          set -uo pipefail

          # On a root-squashed NFS export none of mkdir/chown/chmod can work -
          # root here is nobody there. So none of them are fatal; the only thing
          # that actually matters is whether the opengym user can write, and
          # that is what gets checked. Locally all three succeed and the check
          # is a formality.
          if [ ! -d ${dataDir} ]; then
            mkdir -p ${dataDir} || true
          fi
          chown opengym:opengym ${dataDir} 2>/dev/null || true
          chmod 0750 ${dataDir} 2>/dev/null || true

          if [ ! -d ${dataDir} ]; then
            echo "[opengym] ${dataDir} does not exist and could not be created."
            echo "[opengym] If this is a root-squashed NFS export, create it on"
            echo "[opengym] the server and give it to uid 995 / gid 992."
            exit 1
          fi

          if ! ${pkgs.util-linux}/bin/runuser -u opengym -- \
                 test -w ${dataDir}; then
            echo "[opengym] ${dataDir} exists but is not writable by opengym"
            echo "[opengym] (uid 995 / gid 992). Fix the ownership on the"
            echo "[opengym] server that exports it."
            exit 1
          fi

          echo "[opengym] data directory ready: ${dataDir}"
        '';
      };
    };

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
      after = [
        "network-online.target"
        "opengym-data-init.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "opengym-data-init.service" ];

      # No-op when dataDir is local. When it is on NFS this is what makes the
      # difference between waiting for the automount and starting up against a
      # bare mountpoint - which would look like a brand new instance with every
      # profile gone, and then write a fresh db.json underneath the mount.
      unitConfig.RequiresMountsFor = [ dataDir ];

      environment = {
        PORT = toString cfg.apiPort;
        DATA_DIR = dataDir;
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
        ReadWritePaths = [ dataDir ];
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
