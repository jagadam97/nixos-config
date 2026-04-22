# Nauvoo - Main workstation configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
  ];

  # Hostname
  networking.hostName = "razorback";

  # User configuration
  users.users.jagadam97 = {
    isNormalUser = true;
    description = "jagadam97";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" ];
    linger = true;
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
  system.stateVersion = "26.05";

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
    owner = "jagadam97";
  };
}
