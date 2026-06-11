# Distributed builds: offload *Linux* builds to nauvoo over Tailscale SSH.
#
# nauvoo builds x86_64-linux natively + aarch64-linux via binfmt
# (boot.binfmt.emulatedSystems in hosts/nauvoo/default.nix).
#
# No nauvoo-side config needed: user `dj` is already a trusted-user
# (modules/common/nix-settings.nix) and this key is already authorized.
#
# NOTE: macOS runs Nix in daemon mode, so the offload SSH is opened by the
# root-owned nix-daemon — not your shell. Root just reads the key file below;
# the key must have NO passphrase (root has no agent/keychain to unlock it).
{ config, lib, pkgs, ... }:

{
  nix.distributedBuilds = true;

  # Pull build deps from binary caches on the builder, not back through the Mac.
  nix.settings.builders-use-substitutes = true;

  nix.buildMachines = [
    {
      hostName = "nauvoo"; # Tailscale MagicDNS name
      sshUser = "dj";
      sshKey = "/Users/dinesh.reddy/.ssh/id_ed25519"; # your existing key
      protocol = "ssh-ng";
      systems = [ "x86_64-linux" "aarch64-linux" ];
      maxJobs = 8;
      speedFactor = 2;
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    }
  ];

  # root's nix-daemon opens the offload SSH; teach root's ssh client the host
  # and auto-accept nauvoo's key on first connect (root has no known_hosts yet).
  environment.etc."ssh/ssh_config.d/100-nix-remote-builder.conf".text = ''
    Host nauvoo
      User dj
      IdentityFile /Users/dinesh.reddy/.ssh/id_ed25519
      StrictHostKeyChecking accept-new
  '';
}
