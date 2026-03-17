# SSH configuration
{ config, pkgs, ... }:

{
  services.openssh = {
    enable = true;

    settings = {
      # Key-only authentication - no passwords over SSH
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;

      # Allow modern + common older MACs for compatibility
      Macs = [
        "hmac-sha2-256"
        "hmac-sha2-512"
        "hmac-sha1"
        "umac-64@openssh.com"
        "umac-128@openssh.com"
      ];
    };
  };
}
