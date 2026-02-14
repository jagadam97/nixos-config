# Folding@home distributed computing
{ config, pkgs, ... }:

{
  sops.secrets.fah_passkey = {
    format = "dotenv";
    key = "FAH_PASSKEY";
  };

  services.foldingathome = {
    enable = true;

    user = "jagadam97";
    team = 223518;

    extraArgs = [
      "--cpus=8"
      "--passkey-file=${config.sops.secrets.fah_passkey.path}"
    ];
  };
}
