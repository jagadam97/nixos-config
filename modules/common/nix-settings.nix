# Nix settings and optimizations
{ config, pkgs, ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "dj" "jagadam97" ];
    # i686-linux: native 32-bit support on x86_64 (needed for 32-bit NVIDIA libs).
    # aarch64-linux: cross-builds via QEMU binfmt (where boot.binfmt is enabled).
    extra-platforms = [ "i686-linux" "aarch64-linux" ];
  };

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.settings.auto-optimise-store = true;
}
