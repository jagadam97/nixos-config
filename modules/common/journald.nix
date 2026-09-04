{ config, pkgs, ...}:
{
  services.journald.settings.Journal = {
    SystemMaxUse = "300M";
    SystemMaxFileSize = "50M";
    MaxRetentionSec = "2week";
    Compress = "yes";
  };
}
