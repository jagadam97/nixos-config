# Desktop environment (KDE Plasma 6)
{ config, pkgs, lib, ... }:

{
  imports = [
    ./kde.nix
    ./pipewire.nix
  ];

  # Additional desktop packages
  environment.systemPackages = with pkgs; [
    vscode
    zed-editor
    firefox
    chafa
  ];

  # X11/Wayland settings
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
