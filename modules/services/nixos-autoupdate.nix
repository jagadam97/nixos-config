# Auto-update NixOS config from private GitHub repo
# - Clones repo to /var/lib/nixos-config if not present
# - Runs every 5 minutes, checks for new commits on main
# - If changes detected, runs nixos-rebuild switch
# - Logs to journald (journalctl -u nixos-autoupdate)
{
  config,
  pkgs,
  lib,
  ...
}:

let
  repoUrl = "git@github.com:jagadam97/nixos-config.git";
  repoDir = "/var/lib/nixos-config";
  hostname = config.networking.hostName;

  updateScript = pkgs.writeShellScript "nixos-autoupdate" ''
    set -euo pipefail

    REPO="${repoDir}"
    REMOTE="${repoUrl}"
    FLAKE_TARGET="${hostname}"

    echo "[nixos-autoupdate] Starting check at $(date)"

    # Clone if repo doesn't exist yet
    if [ ! -d "$REPO/.git" ]; then
      echo "[nixos-autoupdate] Cloning repo..."
      ${pkgs.git}/bin/git clone "$REMOTE" "$REPO"
      echo "[nixos-autoupdate] Clone complete, triggering initial build..."
      ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake "$REPO#$FLAKE_TARGET"
      echo "[nixos-autoupdate] Initial build done."
      exit 0
    fi

    # Fetch latest from origin
    cd "$REPO"
    ${pkgs.git}/bin/git fetch origin main 2>&1

    LOCAL=$(${pkgs.git}/bin/git rev-parse HEAD)
    REMOTE_SHA=$(${pkgs.git}/bin/git rev-parse origin/main)

    if [ "$LOCAL" = "$REMOTE_SHA" ]; then
      echo "[nixos-autoupdate] Already up to date ($LOCAL). Nothing to do."
      exit 0
    fi

    echo "[nixos-autoupdate] New commits detected: $LOCAL -> $REMOTE_SHA"
    ${pkgs.git}/bin/git pull --ff-only origin main

    echo "[nixos-autoupdate] Running nixos-rebuild switch..."
    ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake "$REPO#$FLAKE_TARGET"
    echo "[nixos-autoupdate] Rebuild complete."
  '';
in
{
  # Ensure repo dir exists with correct ownership
  systemd.tmpfiles.rules = [
    "d ${repoDir} 0755 root root -"
  ];

  # The update service
  systemd.services.nixos-autoupdate = {
    description = "Check and apply NixOS config updates from GitHub";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = updateScript;
      # Use kayda's SSH key for git
      Environment = [
        "HOME=/root"
        "GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh -i /home/jagadam97/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"
      ];
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Timer: run every 5 minutes
  systemd.timers.nixos-autoupdate = {
    description = "Periodic NixOS config update check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min"; # first run 2 min after boot
      OnUnitActiveSec = "5min"; # then every 5 minutes
      Persistent = true; # catch up if missed while offline
    };
  };
}
