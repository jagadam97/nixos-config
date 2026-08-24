# Push pella's closure from kayda after kayda's own autoupdate succeeds.
#
# pella cannot pull for itself: evaluating its config needs the private
# homelab-scrapper input (GitHub creds it does not have), and it is a 4GB Pi on
# a microSD, so building an aarch64 closure locally is out. So kayda - which
# already clones the repo, holds root's GitHub key, and runs aarch64 under QEMU
# binfmt - builds and pushes.
#
# Trigger is systemd OnSuccess= on nixos-autoupdate, not a timer of its own.
# That means pella is only ever deployed from a tree that kayda has already
# built and switched to, so kayda is the canary: if a commit breaks the build,
# nixos-autoupdate fails and this never runs. There is deliberately no CI gate
# here - pella is not in the CI matrix, kayda's own build is the gate.
#
# nixos-autoupdate exits 0 on every no-op tick (every 5 min), so this unit is
# triggered constantly. The SHA guard below makes those ticks free.
{
  config,
  pkgs,
  inputs,
  ...
}:

let
  # The same clone nixos-autoupdate maintains. Read-only here: that service
  # owns the fetch/reset, and OnSuccess= guarantees we only look at it after it
  # has finished, so there is no race on the working tree.
  repoDir = "/var/lib/nixos-config";
  stateDir = "/var/lib/pella-autodeploy";
  stateFile = "${stateDir}/last-deployed-sha";

  # LAN address, not the Tailscale name - same reason as the deploy node in
  # flake.nix: magic rollback needs the deployer's reconnect to survive
  # activation restarting tailscaled.
  pellaHost = "192.168.4.230";

  # The key pella authorises for root logins lives in jagadam97's homedir, not
  # root's (hosts/pella/default.nix pins `kayda@nixos`). root can read it, and
  # root is what this unit has to run as: fetching the private
  # homelab-scrapper input uses /root/.ssh/id_ed25519.
  deployKey = "/home/jagadam97/.ssh/id_ed25519";

  # Passed to deploy-rs with --ssh-opts, which overrides the node's sshOpts.
  # The flake keeps a minimal sshOpts for hand-run deploys; the extra
  # non-interactive options only belong to this unit.
  sshOpts = "-i ${deployKey} -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10";

  discordWebhook = config.services.nixos-autoupdate.discordWebhookUrl;
  deployRs = inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Same secret nixos-autoupdate uses; declared by that module, which kayda
  # already imports. The token needs commit-status read/write.
  githubTokenFile = config.sops.secrets.github_token.path;

  deployScript = pkgs.writeShellScript "pella-autodeploy" ''
    set -euo pipefail

    REPO="${repoDir}"
    STATE="${stateFile}"
    SSH_OPTS="${sshOpts}"
    GITHUB_TOKEN=$(cat "${githubTokenFile}")
    GITHUB_REPO="jagadam97/nixos-config"

    # Reports the pella deploy back onto the commit kayda deployed, under its
    # own context so it sits beside nixos-autoupdate/kayda instead of
    # overwriting it. Never fatal: a status post failing must not roll pella
    # back.
    github_status() {
      local state="$1"
      local description="$2"
      [ -z "''${HEAD:-}" ] && return 0
      ${pkgs.curl}/bin/curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPO/statuses/$HEAD" \
        -d "{\"state\":\"$state\",\"description\":\"$description\",\"context\":\"pella-autodeploy/pella\"}" \
        >/dev/null || true
    }

    cd "$REPO"

    HEAD=$(${pkgs.git}/bin/git rev-parse HEAD)
    LAST=$(cat "$STATE" 2>/dev/null || echo "none")

    if [ "$HEAD" = "$LAST" ]; then
      echo "[pella-autodeploy] $HEAD already handled. Nothing to do."
      exit 0
    fi

    echo "[pella-autodeploy] New tree $LAST -> $HEAD, building pella under binfmt"

    # From here on every exit path reports. The trap covers the build, the
    # reachability probe and the deploy itself.
    github_status pending "building and deploying pella from kayda"
    trap 'github_status failure "pella deploy failed — check journalctl -u pella-autodeploy on kayda"' ERR

    # Build first so a broken pella config fails here, before anything touches
    # the box. Emulated, but the closure is almost entirely cached.
    PROFILE=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths \
      "$REPO#deploy.nodes.pella.profiles.system.path")

    echo "[pella-autodeploy] Built $PROFILE"

    # Skip pointless activations. Most commits touch other hosts, and this is a
    # router - do not restart its services to apply an identical closure.
    # Best-effort: if pella is unreachable, fall through and let deploy-rs
    # produce the real error.
    CURRENT=$(${pkgs.openssh}/bin/ssh $SSH_OPTS "root@${pellaHost}" \
      "readlink -f /nix/var/nix/profiles/system" 2>/dev/null || echo "unknown")

    if [ "$PROFILE" = "$CURRENT" ]; then
      echo "[pella-autodeploy] pella already on this closure. Recording $HEAD."
      echo "$HEAD" > "$STATE"
      github_status success "pella already on this closure — nothing to activate"
      exit 0
    fi

    echo "[pella-autodeploy] pella is on $CURRENT, deploying"

    # --skip-checks: `nix flake check` was already implied by the build above,
    # and running it here would re-evaluate every host on an emulated builder.
    # --no-progress: progress bars are noise in the journal.
    ${deployRs}/bin/deploy \
      --skip-checks \
      --no-progress \
      --ssh-opts "$SSH_OPTS" \
      "$REPO#pella"

    trap - ERR
    echo "$HEAD" > "$STATE"

    github_status success "pella deployed from kayda"

    ${pkgs.curl}/bin/curl -s -X POST "${discordWebhook}" \
      -H "Content-Type: application/json" \
      -d "{\"embeds\":[{\"title\":\"Pella Deploy Success\",\"description\":\"Pushed from \`kayda\` at \`$HEAD\`.\\nProfile: \`$PROFILE\`\",\"color\":3066993}]}" \
      || true

    echo "[pella-autodeploy] Deploy complete."
  '';

  notifyFailureScript = pkgs.writeShellScript "pella-autodeploy-notify-failure" ''
    ${pkgs.curl}/bin/curl -s -X POST "${discordWebhook}" \
      -H "Content-Type: application/json" \
      -d "{\"embeds\":[{\"title\":\"Pella Deploy Failed\",\"description\":\"Push from \`kayda\` failed.\\nCheck: \`journalctl -u pella-autodeploy\`\\nIf activation started, magic rollback has already reverted pella.\",\"color\":15158332}]}" \
      || true
  '';
in
{
  # Merges with the onFailure= already set there; nixos-autoupdate does not
  # define onSuccess itself.
  systemd.services.nixos-autoupdate.onSuccess = [ "pella-autodeploy.service" ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 root root -"
  ];

  systemd.services.pella-autodeploy = {
    description = "Build and deploy pella's closure from kayda";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    onFailure = [ "pella-autodeploy-notify-failure.service" ];

    # Same reason as nixos-autoupdate: a kayda activation must not SIGTERM an
    # in-flight deploy. Killing the deployer mid-activation is exactly the
    # case magic rollback treats as a failed deploy.
    restartIfChanged = false;

    path = with pkgs; [
      nix
      openssh
      git
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = deployScript;
      Environment = [ "HOME=/root" ];
      StandardOutput = "journal";
      StandardError = "journal";
      # Emulated aarch64 builds are slow and unbounded.
      TimeoutStartSec = "infinity";
    };
  };

  systemd.services.pella-autodeploy-notify-failure = {
    description = "Discord failure notification for pella-autodeploy";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = notifyFailureScript;
    };
  };
}
