# Desktop environment (shared base - DE imported per-host)
{ config, pkgs, lib, ... }:

{
  imports = [
    ./pipewire.nix
  ];

  # Additional desktop packages
  environment.systemPackages = with pkgs; [
    vscode
    zed-editor
    firefox
    chafa
    brave
  ];

  # X11/Wayland settings
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
