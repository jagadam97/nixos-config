# User-specific packages
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Development tools
    go
    cmake
    gcc
    claude-code

    # Editors
    vscode
    zed-editor

    # System utilities
    mosh
    aria2
    ffmpeg
    chafa
  ];
}
