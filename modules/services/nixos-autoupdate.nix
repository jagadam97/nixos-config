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
  sshKey = "/home/jagadam97/.ssh/id_ed25519";
  hostname = config.networking.hostName;

  # Wrapper so GIT_SSH_COMMAND has no spaces (systemd Environment= limitation)
  gitSshWrapper = pkgs.writeShellScript "git-ssh-wrapper" ''
    exec ${pkgs.openssh}/bin/ssh \
      -i ${sshKey} \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/root/.ssh/known_hosts \
      "$@"
  '';

  updateScript = pkgs.writeShellScript "nixos-autoupdate" ''
    set -euo pipefail

    export GIT_SSH_COMMAND="${gitSshWrapper}"
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

    # Don't rebuild while Nomad has running jobs - it will kill active ffmpeg encodes
    RUNNING_JOBS=$(${pkgs.nomad}/bin/nomad job status 2>/dev/null \
      | grep -c "running" || true)
    if [ "$RUNNING_JOBS" -gt 0 ]; then
      echo "[nixos-autoupdate] Nomad has $RUNNING_JOBS running job(s), skipping rebuild to avoid interruption. Will retry next cycle."
      exit 0
    fi

    ${pkgs.git}/bin/git pull --ff-only origin main

    echo "[nixos-autoupdate] Running nixos-rebuild switch..."
    ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake "$REPO#$FLAKE_TARGET"
    echo "[nixos-autoupdate] Rebuild complete."
    rm -rf "$REPO"
  '';
in
{
  # Ensure repo dir and root .ssh dir exist
  systemd.tmpfiles.rules = [
    "d ${repoDir} 0755 root root -"
    "d /root/.ssh 0700 root root -"
  ];

  # Pre-trust GitHub's host key for root
  environment.etc."ssh/ssh_known_hosts".text = ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
    github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
    github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C4G/OsES4AqazIoVCyqqM91MaFBNbaRLbCMwXOIHFJBBtRtexiNefNgNXSfGJf+9bF5bRp7EIX98pRLzLBDWqcCJUh7Zs7VJMwDBGVb7gbTZxS1NSO0iLKcbn51bNMRa9mGG8K2SmFWsK7/q5cFP5rXeP4HL1VBXC0Bd7UTkMFLwHE4YZsRwjJiE4HrPxm8w7SF3E1kSSdxK3LqSf30YJiKkLAGRWEm5cqIJtjHQhEiABJt1i1E7mk4F6GRQ9tV3G1tspOPCi5xSf7qHT+5qpxDX41BZG6D0HkCZfS13xJFRNi3hHqKpOZaovVGQf8V9VL4SzgpwkSJWczr5U52lAklGHy2m5wY0qEeZGTxwb7qXmKP/8IUPKXhF0t2FQf1E7EeCrpSNO1n6d1oZzpPZ0gGQHJnkTq5c+mP/qp5R1WLpNq+rkLzpVRQGqJCLqfPWJgV+Mm5JT3q6Q=
  '';

  # The update service
  systemd.services.nixos-autoupdate = {
    description = "Check and apply NixOS config updates from GitHub";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = updateScript;
      Environment = [ "HOME=/root" ];
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
