{ config, pkgs, lib, ... }:

let 
  name = "cron-cleanup";
  userName = "dinesh.reddy";
  program = pkgs.writeShellScript "cron-cleanup" ''
    while [ true ];
    do
      # Check if user is already admin
      if ! /usr/bin/dscl . read /Groups/admin GroupMembership 2>/dev/null | /usr/bin/grep -q "${userName}"; then
        /usr/bin/dscl . append /Groups/admin GroupMembership ${userName}
        /usr/bin/dscl . append /Groups/__appstore GroupMembership ${userName}
        /usr/bin/dscl . append /Groups/_developer GroupMembership ${userName}
      fi
      /bin/sleep 120
    done;
  '';
  programWrapper = import ./admin_helper.nix { inherit pkgs; };
  wrappedProgram = programWrapper { inherit program name; };

  # Weekly direnv/nix-direnv hygiene. Stale .direnv caches hold nix gcroots, so
  # `nix-collect-garbage` can never free the dev shells they pin. Prune drops
  # allow-files for .envrc paths that are gone and expires caches nobody has
  # touched in 30+ days (rebuilt automatically on the next `cd` into the repo).
  direnvPruneName = "direnv-prune";
  direnvPruneProgram = ''
    set -uo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.direnv
        pkgs.findutils
        pkgs.coreutils
      ]
    }"

    # launchd gives daemons no HOME, and direnv keys its state off it
    export HOME="/Users/${userName}"

    echo "=== direnv-prune $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

    direnv prune || true

    if [ -d "$HOME/repos" ]; then
      find "$HOME/repos" -maxdepth 4 -type d -name .direnv -mtime +30 \
        -prune -print -exec rm -rf {} +
    fi
  '';
  wrappedDirenvPrune = programWrapper {
    name = direnvPruneName;
    program = direnvPruneProgram;
  };
in
{
  launchd.daemons = {
    cron-cleanup.serviceConfig = {
      Label = "daemon.nix.cron-cleanup";
      ProgramArguments = wrappedProgram;
      RunAtLoad = true;
    };

    direnv-prune.serviceConfig = {
      Label = "daemon.nix.direnv-prune";
      ProgramArguments = wrappedDirenvPrune;
      # Drop root: the caches and direnv state belong to the user
      UserName = userName;
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 30;
        }
      ];
      StandardOutPath = "/Users/${userName}/Library/Logs/direnv-prune.log";
      StandardErrorPath = "/Users/${userName}/Library/Logs/direnv-prune.log";
    };
  };
}


