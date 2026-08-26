# Distributed builds: offload Linux builds to alienX (WAN) and razorback (LAN).
#
# alienX is Ubuntu with Determinate Nix — 32 cores, so it takes the bulk of the
# work. Preferred by speedFactor.
#
# razorback is the NixOS desktop on the home LAN — 16 cores, `aarch64-linux`
# binfmt enabled, and a direct Tailscale path. Kept as a fallback and for jobs
# with multi-GB outputs, where the LAN copy back beats alienX's extra cores.
#
# Both users are already trusted by their Nix daemons and this key is authorized.
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
      # NixOS: nix-daemon lives in the system profile.
      hostName = "razorback.owl-coho.ts.net?remote-program=/run/current-system/sw/bin/nix-daemon";
      sshUser = "jagadam97";
      sshKey = "/Users/dinesh.reddy/.ssh/id_ed25519";
      protocol = "ssh-ng";
      systems = [ "x86_64-linux" "aarch64-linux" ];
      maxJobs = 16;
      speedFactor = 2; # fallback: pick with --builders when outputs are big
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "uid-range" "kvm" ];
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUQ2R2JlWjlTNVlkTzM5a2VPWURsbUJPYUx0ZHEwMlRYU0VVeUVGOG5BUlQgcm9vdEByYXpvcmJhY2sK";
    }
    {
      # Determinate Nix is not on PATH for non-interactive SSH sessions.
      hostName = "alienx.owl-coho.ts.net?remote-program=/nix/var/nix/profiles/default/bin/nix-daemon";
      sshUser = "dj";
      sshKey = "/Users/dinesh.reddy/.ssh/id_ed25519"; # your existing key
      protocol = "ssh-ng";
      systems = [ "x86_64-linux" "aarch64-linux" ];
      maxJobs = 32;
      speedFactor = 3; # preferred: 32 cores
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "uid-range" "kvm" ];
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUROcXlwazVwczFBM1h4cVAvWFpuQmJ2Z1hldmpzQzVCaEFLL05Mb0V6OEMgcm9vdEBtYW10aGEtMk4zNzJMMUtIUTJGCg==";
    }
  ];

  # Override per command with: nix build --builders "$NAUVOO_NIX_BUILDERS" ...
  environment.variables.NAUVOO_NIX_BUILDERS = "ssh-ng://dj@nauvoo.owl-coho.ts.net?remote-program=/run/current-system/sw/bin/nix-daemon x86_64-linux,aarch64-linux /Users/dinesh.reddy/.ssh/id_ed25519 16 1 nixos-test,benchmark,big-parallel,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUVaYnU0Wm9zUW1DUlI0dWVIeVR6VWx5Rjk5a1prYzRpNVh6dzI5OXB5N0Ugcm9vdEBuYXV2b28K";
}
