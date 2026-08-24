# FileBrowser Quantum (gtsteffaniak/filebrowser) on pella.
#
# This is NOT the upstream filebrowser/filebrowser that `services.filebrowser`
# in nixpkgs configures. Quantum is a fork with its own config model - a single
# YAML file, a SQLite *index* (not a Bolt settings DB), and a handful of
# FILEBROWSER_* env vars for secrets. Nothing is shared with the original, and
# nixpkgs ships no module for it, so the unit below is hand-rolled.
#
# The point of running it here is search: one index over the Pi's own root plus
# the NFS mounts, so "where is that file" is answerable from a browser.
#
# It runs as root because that is what "see every folder" means on a box where
# most of the interesting paths are root-owned, and it is read-write: copy,
# move and delete are the point, not just search.
#
# Understand what that means before opening the port. Anyone who reaches it and
# has the admin password has root-equivalent read *and write* over this host:
# they can read /etc, edit anything under /etc/nixos or /var/lib, and delete
# system files. The only things standing in front of that are the LAN boundary,
# the firewall, and the password in sops. Nothing here is hardened against a
# logged-in user - it is not meant to be.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.filebrowserQuantum;

  stateDir = "/var/lib/filebrowser-quantum";
  cacheDir = "/var/cache/filebrowser-quantum";

  # The NFS mounts from modules/services/nfs-mounts.nix. Indexed as their own
  # sources rather than by letting the root walk into /mnt: they are hard
  # x-systemd.automount mounts on another box, and separate sources let them
  # carry their own (much longer) indexing interval.
  nfsMounts = [
    "/mnt/bx1000"
    "/mnt/bx500"
    "/mnt/hd4000"
  ];

  settings = {
    server = {
      port = cfg.port;
      listen = cfg.listenAddress;
      baseURL = "/";
      database = "${stateDir}/index.db";
      cacheDir = cacheDir;
      # journald already timestamps and colourises nothing.
      logging = [
        {
          levels = "info|warning|error";
          output = "stdout";
          noColors = true;
        }
      ];

      sources = [
        {
          path = "/";
          name = "pella";
          config = {
            defaultEnabled = true;
            indexingIntervalMinutes = 60;
            rules = [
              # /nix alone is millions of paths on a microSD. Indexing it would
              # dwarf everything else in the index and buy nothing: store paths
              # are not what you search for.
              { folderPath = "/nix"; }
              # Kernel and runtime pseudo-filesystems. Walking these is at best
              # pointless and at worst a way to block on a device node.
              { folderPath = "/proc"; }
              { folderPath = "/sys"; }
              { folderPath = "/dev"; }
              { folderPath = "/run"; }
              # Indexed as their own sources below.
              { folderPath = "/mnt"; }
              # Do not index the index.
              { folderPath = stateDir; }
              { folderPath = cacheDir; }
              # /nix/store is excluded, but symlinks into it are everywhere -
              # /etc, /run/current-system, every profile. Following them would
              # re-index the store through the back door.
              { ignoreSymlinks = true; }
            ];
          };
        }
      ]
      ++ map (m: {
        path = m;
        name = baseNameOf m;
        config = {
          defaultEnabled = true;
          # These live on 192.168.4.240 and are large. Re-walking them from a
          # Pi over NFS every hour would keep the link and the card busy for
          # very little; once a day is enough for a search index.
          indexingIntervalMinutes = 1440;
          rules = [ { ignoreSymlinks = true; } ];
        };
      }) nfsMounts;
    };

    auth.methods.password = {
      enabled = true;
      minLength = 8;
      signup = false;
    };
  };

  configFile = (pkgs.formats.yaml { }).generate "filebrowser-quantum.yaml" settings;
in
{
  options.services.filebrowserQuantum = {
    enable = lib.mkEnableOption "FileBrowser Quantum";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8087;
      description = "Port the web UI listens on.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to bind. Quantum's key for this is `listen`.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the UI port in the host firewall.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an env file holding the secrets Quantum reads from the
        environment rather than the config file. At minimum:

          FILEBROWSER_ADMIN_PASSWORD=...

        Optionally FILEBROWSER_JWT_TOKEN_SECRET (otherwise a random key is
        generated on each start, which invalidates sessions across restarts).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.filebrowser-quantum = {
      description = "FileBrowser Quantum";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        # Root, deliberately: the whole point is reading paths that are not
        # world-readable. See the header.
        User = "root";
        ExecStart = "${lib.getExe pkgs.filebrowser-quantum} -c ${configFile}";
        EnvironmentFile = cfg.environmentFile;
        StateDirectory = "filebrowser-quantum";
        CacheDirectory = "filebrowser-quantum";
        WorkingDirectory = stateDir;
        Restart = "on-failure";
        RestartSec = 10;

        # No ProtectSystem/ProtectHome/PrivateTmp: every one of them would
        # either hide a directory this service exists to show or make it
        # unwritable, and writing is wanted here. What is left are the
        # restrictions that cost nothing - the service has no business loading
        # kernel modules, rewriting sysctls or creating setuid files.
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
