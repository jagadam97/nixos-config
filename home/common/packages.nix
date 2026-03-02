# User-specific packages
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Development tools
    go
    cmake
    gcc
    claude-code
    github-copilot-cli

    # Editors
    vscode

    # System utilities
    mosh
    aria2
    ffmpeg
    chafa
    zellij
  ];
}
