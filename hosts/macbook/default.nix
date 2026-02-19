# MacBook - Apple Silicon Mac
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./gui-apps.nix
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable nix-darwin's Nix management
  nix.enable = true;
  nix.package = pkgs.nix;

  # Enable nix-command and flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Trust the current user for daemon operations
  nix.settings.trusted-users = [ "root" "@admin" "dinesh.reddy" ];

  # Hostname
  networking.hostName = "macbook";
  networking.computerName = "Dinesh's MacBook";

  # Primary user for nix-darwin
  system.primaryUser = "dinesh.reddy";

  # Enable sudo with Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # Keyboard settings
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;

  # Fonts
  fonts.packages = with pkgs; [
    pkgs.nerd-fonts.fira-code
    pkgs.nerd-fonts.jetbrains-mono
  ];

  # Shells
  environment.shells = with pkgs; [ zsh ];
  environment.systemPath = [ "/opt/homebrew/bin" ];
  environment.pathsToLink = [ "/Applications" ];

  # GUI apps at system level for Spotlight visibility in /Applications/Nix Apps/
  environment.systemPackages = with pkgs; [
    alacritty
    iterm2
    vscode
    slack
    postman
    bitwarden-desktop
    claude-code
    notion-app
  ];

  # System defaults
  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false;
    dock.orientation = "bottom";
    finder.AppleShowAllExtensions = true;
    finder.FXPreferredViewStyle = "clmv";
    loginwindow.GuestEnabled = false;
    NSGlobalDomain.AppleKeyboardUIMode = 3;
    NSGlobalDomain.InitialKeyRepeat = 15;
    NSGlobalDomain.KeyRepeat = 2;
    NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
    screensaver.askForPasswordDelay = 10;
  };

  # Timezone (macOS uses legacy Asia/Calcutta name)
  time.timeZone = "Asia/Calcutta";

  # System state version
  system.stateVersion = 5;

  # User
  users.users."dinesh.reddy" = {
    name = "dinesh.reddy";
    home = "/Users/dinesh.reddy";
    shell = pkgs.zsh;
  };

  # Launch daemons (for things that need to run as root)
  launchd.daemons = {
    # Add any launch daemons here if needed
  };
}