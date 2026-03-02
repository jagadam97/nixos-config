# GUI Applications managed via Homebrew casks
{ config, pkgs, lib, ... }:

{
  # Enable Homebrew for casks that aren't in nixpkgs
  homebrew = {
    enable = true;
    onActivation.autoUpdate = true;
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
      "bitwarden"
      "brave-browser"
      "font-fira-code"
      "font-powerline-symbols"
      "ghostty"
      "iterm2"
      "notion"
      "notion-calendar"
      "postman"
      "rectangle"
      "visual-studio-code"
      "vivaldi"
      "zed"
    ];
  };
}
