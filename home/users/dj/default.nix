# Home configuration for user 'dj'
{ config, pkgs, ... }:

{
  imports = [
    ../../common
  ];

  home.username = "dj";
  home.homeDirectory = "/home/dj";

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;

  home.stateVersion = "24.11";
}
