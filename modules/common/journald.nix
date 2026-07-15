{ config, pkgs, ...}:
{
  services.journald.extraConfig = ''
    SystemMaxUse=300M
    SystemMaxFileSize=50M
    MaxRetentionSec=2week
    Compress=yes
  '';
}
