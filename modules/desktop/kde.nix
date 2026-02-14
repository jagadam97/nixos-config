# KDE Plasma 6 desktop environment
{ config, pkgs, lib, ... }:

{
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Disable auto-login
  services.displayManager.autoLogin = {
    enable = false;
    user = "dj";
  };

  # Disable kwallet
  security.pam.services = {
    login.kwallet.enable = lib.mkForce false;
    sddm.kwallet.enable = lib.mkForce false;
  };
}
