# SSH configuration
{ config, pkgs, ... }:

{
  services.openssh = {
    enable = true;

    # Allow modern + common older MACs for compatibility
    settings.Macs = [
      "hmac-sha2-256"
      "hmac-sha2-512"
      "hmac-sha1"
      "umac-64@openssh.com"
      "umac-128@openssh.com"
    ];
  };
}
