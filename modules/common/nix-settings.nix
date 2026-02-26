# Nix settings and optimizations
{ config, pkgs, ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "dj" ];
    # Enable building for aarch64-linux via QEMU binfmt
    extra-platforms = [ "aarch64-linux" ];
  };

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.settings.auto-optimise-store = true;
}
