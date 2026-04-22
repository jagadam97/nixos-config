# GNOME desktop environment
{ config, pkgs, lib, ... }:

{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
}
