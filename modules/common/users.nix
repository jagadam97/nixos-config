# User configuration
{ config, pkgs, ... }:

{
  users.users.dj = {
    isNormalUser = true;
    description = "dj";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" ];
    linger = true;
  };
}
