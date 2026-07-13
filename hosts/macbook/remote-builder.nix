# Distributed builds: offload Linux builds to alienX over Tailscale SSH.
#
# alienX is Ubuntu with Determinate Nix. User `dj` is already trusted by its
# Nix daemon, and this key is already authorized.
#
# NOTE: macOS runs Nix in daemon mode, so the offload SSH is opened by the
# root-owned nix-daemon, which cannot use the user's SSH config. Root reads the
# key file below directly;
# the key must have NO passphrase (root has no agent/keychain to unlock it).
{ config, lib, pkgs, ... }:

{
  nix.distributedBuilds = true;

  # Pull build deps from binary caches on the builder, not back through the Mac.
  nix.settings.builders-use-substitutes = true;

  nix.buildMachines = [
    {
      # Determinate Nix is not on PATH for non-interactive SSH sessions.
      hostName = "alienx.owl-coho.ts.net?remote-program=/nix/var/nix/profiles/default/bin/nix-daemon";
      sshUser = "dj";
      sshKey = "/Users/dinesh.reddy/.ssh/id_ed25519"; # your existing key
      protocol = "ssh-ng";
      systems = [ "x86_64-linux" "aarch64-linux" ];
      maxJobs = 32;
      speedFactor = 2;
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "uid-range" "kvm" ];
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUROcXlwazVwczFBM1h4cVAvWFpuQmJ2Z1hldmpzQzVCaEFLL05Mb0V6OEMgcm9vdEBtYW10aGEtMk4zNzJMMUtIUTJGCg==";
    }
  ];

  # Override per command with: nix build --builders "$NAUVOO_NIX_BUILDERS" ...
  environment.variables.NAUVOO_NIX_BUILDERS = "ssh-ng://dj@nauvoo.owl-coho.ts.net?remote-program=/run/current-system/sw/bin/nix-daemon x86_64-linux,aarch64-linux /Users/dinesh.reddy/.ssh/id_ed25519 16 1 nixos-test,benchmark,big-parallel,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUVaYnU0Wm9zUW1DUlI0dWVIeVR6VWx5Rjk5a1prYzRpNVh6dzI5OXB5N0Ugcm9vdEBuYXV2b28K";
}
