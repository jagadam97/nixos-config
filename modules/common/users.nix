# User configuration
{ config, pkgs, ... }:

{
  users.users.dj = {
    isNormalUser = true;
    description = "dj";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" ];
    linger = true;
  };

   users.users.jagadam97 = {
    isNormalUser = true;
    description = "jagadam97";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" ];
    linger = true;
  };
}
