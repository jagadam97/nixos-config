{ config, pkgs, lib, ... }:

let 
  name = "mkAdmin";
  userName = "dinesh.reddy";
  program = pkgs.writeShellScript "mkAdmin" ''
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
    mkAdmin.serviceConfig = {
      Label = "daemon.nix.mkAdmin";
      ProgramArguments = wrappedProgram;
      RunAtLoad = true;
    };
  };
}


