# GUI Applications managed via Homebrew casks
{ config, pkgs, lib, ... }:

{
  # Enable Homebrew for casks that aren't in nixpkgs
  homebrew = {
    enable = true;
    onActivation.autoUpdate = false;
    onActivation.cleanup = "zap";
    onActivation.upgrade = true;

    taps = [
      # Fonts are now in homebrew/cask, no need for cask-fonts tap
    ];

    brews = [
      # CLI tools that might not be in nixpkgs or you prefer from brew
      # Most CLI tools are migrated to Nix, add any remaining ones here
    ];

    casks = [
      "antigravity"
      "bitwarden"
      "brave-browser"
      "claude-code"
      "font-fira-code"
      "font-powerline-symbols"
      "ghostty"
      "github"
      "google-chrome"
      "iterm2"
      "libreoffice"
      "macfuse"
      "notion"
      "notion-calendar"
      "postman"
      "rectangle"
      "slack"
      "visual-studio-code"
      "vivaldi"
    ];
  };
}