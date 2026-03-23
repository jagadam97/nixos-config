# SSH configuration
{ config, pkgs, ... }:
let isKayda = config.networking.hostName == "kayda";

in
{
  services.openssh = {
    enable = true;

    settings = {
      PasswordAuthentication = !isKayda;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = !isKayda;

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
