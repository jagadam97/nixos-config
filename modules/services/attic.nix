{ config, ... }:
{
  sops.secrets.attic_token = { };

  services.atticd = {
    enable = true;
    environmentFile = config.sops.secrets.attic_token.path;
    settings.compression = {
      type = "xz";
      level = 9;
    };
  };
}
