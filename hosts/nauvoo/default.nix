# Nauvoo - Main workstation configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
  ];

  # Hostname
  networking.hostName = "nauvoo";

  # User configuration
  users.users.dj = {
    isNormalUser = true;
    description = "dj";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" ];
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII0PaRuEIaOKCyD0C/MNT00ZSjCFC+K2LpNzMIDOacd2 dinesh.reddy@macbook"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXs8gealQWXMlEN++Ew7V4EqUFf7Cd+Pnr06ZqtYtdO+SYmA4fdmc9qz5/GI2JJnzs0+sHak4ZCtUihYWN3raeFy/zubKDcycZI44Lcy5SjJhfprg/c/XAags3GuZEnzhlXuqS6Uzeljgps+6gx7eiSHM/tFFV2T3kOoisq0z7kDqsi6Aq1tblMoHyvvUBPjO1huRiqcECrNFA4SnqJMVtspvIpLN74O568NDkc40ZQtcDbdbjZgfRpXx+xVWwO4gGwbrqrAZ8llItrQsGtmC6WoH8c+CUMguJqn7T4cb9nzvbFDDQLKga3DKWqZjnjwAz9lkENfPMWiZeW7kw/Yte99TCDxEm3YGfa6v/QH9JggCscSRg1Zf1UZ3VlEVXev7QvOD16DfDKeCa0z6bfvle6VUi64jVZVYAILdpGFFzrJ18L/ttZdWZYwKIXp18lcWjyGWJDsY6OcdR3XGtI5k4ey8UVa384V5pl36bP1KpD0VN6oAvHWszluHdVpZR4Gk= dines@Optimus"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIg3tJuOvpBMqDvBjBrq5KxkE5ZiK/Dlr28uSSm1mx7U"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHMJ9s1gDUT9aJaLTGDH4gdXAXjbfoBHJYLd9aSxI9qQ jagadam97@razorback"
    ];
  };

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = [ "kvm-amd" "kvm-intel" ];

  # Enable binfmt emulation for aarch64-linux builds
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Networking
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;
  networking.firewall.checkReversePath = lib.mkDefault "loose";

  systemd.services.NetworkManager-wait-online.enable = true;
  systemd.network.wait-online.enable = true;

  # Timezone
  time.timeZone = "Asia/Kolkata";

  # System state version
  system.stateVersion = "26.11";

  # DNS
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  services.resolved.enable = true;

  # Kernel networking tweaks
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 0;
    "net.ipv4.ip_forward" = 1;
  };

  # SOPS configuration for this host
  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";

  sops.secrets.juspay_api_key = {
    # sops-nix needs to know this secret exists in your .yaml file
    # Default owner is root, change if needed
    owner = "dj"; 
  };

}
