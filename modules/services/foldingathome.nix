# Folding@home distributed computing
{ config, pkgs, ... }:

{
  services.foldingathome = {
    enable = true;

    user = "jagadam97";
    team = 223518;

    extraArgs = [
      "--cpus=8"
      "--passkey=c1cf1dde94381870c1cf1dde94381870"
    ];
  };
}
