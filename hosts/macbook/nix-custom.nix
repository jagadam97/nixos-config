# Nix configuration for this Mac.
#
# Nix here is the Determinate Systems install, NOT nix-darwin managed
# (nix.enable = false in ./default.nix). Determinate's /etc/nix/nix.conf
# `!include`s /etc/nix/nix.custom.conf, which is its supported escape hatch
# for user settings. Remote builders live in /etc/nix/machines (the default
# target of the `builders` setting). nix-darwin writes both files below.
#
# The nix daemon reads config at startup. After a switch that changes these:
#   sudo launchctl kickstart -k system/systems.determinate.nix-daemon
{ config, lib, pkgs, ... }:

{
  environment.etc."nix/nix.custom.conf".text = ''
    # Managed by nix-darwin: hosts/macbook/nix-custom.nix
    # (Determinate's nix.conf `!include`s this file)

    # Determinate's nix.conf already enables these via extra-experimental-features;
    # restated here so this file stays self-contained.
    experimental-features = nix-command flakes

    # Trust root, admins, and the primary user for daemon operations
    trusted-users = root @admin dinesh.reddy

    # Remote builders are listed in /etc/nix/machines (written below)
    builders = @/etc/nix/machines

    # Pull build deps from binary caches on the builder, not back through the Mac.
    builders-use-substitutes = true
  '';

  # Distributed builds: offload Linux builds to alienX (WAN) and nauvoo (LAN).
  #
  # alienX is Ubuntu with Determinate Nix — 32 cores, so it takes the bulk of
  # the work. Preferred by speedFactor.
  #
  # nauvoo is the NixOS desktop on the home LAN — 16 cores and a direct
  # Tailscale path. Kept as a fallback and for jobs with multi-GB outputs,
  # where the LAN copy back beats alienX's extra cores.
  #
  # Both users are already trusted by their Nix daemons and this key is authorized.
  #
  # NOTE: macOS runs Nix in daemon mode, so the offload SSH is opened by the
  # root-owned nix-daemon, which cannot use the user's SSH config. Root reads
  # the key file below directly;
  # the key must have NO passphrase (root has no agent/keychain to unlock it).
  #
  # Format: <protocol>://<user>@<host>?<params> <systems> <sshKey> <maxJobs>
  #         <speedFactor> <supportedFeatures> <requiredFeatures> <publicHostKey>
  # ("-" is the placeholder for empty fields — same format nix-darwin writes.)
  environment.etc."nix/machines".text = ''
    # Determinate Nix is not on PATH for non-interactive SSH sessions.
    ssh-ng://dj@alienx.owl-coho.ts.net?remote-program=/nix/var/nix/profiles/default/bin/nix-daemon x86_64-linux,aarch64-linux /Users/dinesh.reddy/.ssh/id_ed25519 32 3 nixos-test,benchmark,big-parallel,uid-range,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUROcXlwazVwczFBM1h4cVAvWFpuQmJ2Z1hldmpzQzVCaEFLL05Mb0V6OEMgcm9vdEBtYW10aGEtMk4zNzJMMUtIUTJGCg==
    ssh-ng://dj@nauvoo.owl-coho.ts.net?remote-program=/run/current-system/sw/bin/nix-daemon x86_64-linux,aarch64-linux /Users/dinesh.reddy/.ssh/id_ed25519 16 2 nixos-test,benchmark,big-parallel,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUVaYnU0Wm9zUW1DUlI0dWVIeVR6VWx5Rjk5a1prYzRpNVh6dzI5OXB5N0Ugcm9vdEBuYXV2b28K
    # razorback (disabled): NixOS desktop, nix-daemon lives in the system profile.
    #ssh-ng://jagadam97@razorback.owl-coho.ts.net?remote-program=/run/current-system/sw/bin/nix-daemon x86_64-linux,aarch64-linux /Users/dinesh.reddy/.ssh/id_ed25519 16 1 nixos-test,benchmark,big-parallel,uid-range,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUQ2R2JlWjlTNVlkTzM5a2VPWURsbUJPYUx0ZHEwMlRYU0VVeUVGOG5BUlQgcm9vdEByYXpvcmJhY2sK
  '';

  # Override per command with: nix build --builders "$NAUVOO_NIX_BUILDERS" ...
  environment.variables.NAUVOO_NIX_BUILDERS = "ssh-ng://dj@nauvoo.owl-coho.ts.net?remote-program=/run/current-system/sw/bin/nix-daemon x86_64-linux,aarch64-linux /Users/dinesh.reddy/.ssh/id_ed25519 16 1 nixos-test,benchmark,big-parallel,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUVaYnU0Wm9zUW1DUlI0dWVIeVR6VWx5Rjk5a1prYzRpNVh6dzI5OXB5N0Ugcm9vdEBuYXV2b28K";
}
