# Home configuration for user 'dj'
{ config, pkgs, ... }:

{
  imports = [
    ../../common
    ./packages.nix
  ];

  home.username = "jagadam97";
  home.homeDirectory = "/home/jagadam97";

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;

  home.stateVersion = "26.05";
}
