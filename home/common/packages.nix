# User-specific packages
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Development tools
    go
    cmake
    gcc

    # System utilities
    mosh
    aria2
    ffmpeg
    chafa
    zellij
  ];
}
