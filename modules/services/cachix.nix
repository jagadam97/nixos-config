# Cachix binary cache configuration
{ config, pkgs, ... }:

{
  # Enable Cachix for faster builds
  nix.settings.substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://jagadam97.cachix.org"
  ];

  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "jagadam97.cachix.org-1:elvOZzw1lYIjid4nA8z87XFxQmQsR40PLnA431V2gAI="
  ];

  # Install Cachix CLI for managing caches
  environment.systemPackages = with pkgs; [
    cachix
  ];
}
