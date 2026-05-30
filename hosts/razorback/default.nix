# Nauvoo - Main workstation configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/services/docker.nix
    ../../modules/services/flaresolver.nix
    ../../modules/services/encrypted-dns.nix
  ];

  # Hostname
  networking.hostName = "razorback";

  environment.systemPackages = with pkgs; [
    handbrake
    jellyfin-desktop
    mpv
  ];

  # Latest kernel for Arrow Lake + HDR Wayland
  boot.kernelPackages = pkgs.linuxPackages_latest;

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
  system.stateVersion = "26.11";

  # Encrypted DNS via dnscrypt-proxy → AGH on beast.jagadam97.uk.
  # ISP interferes with TCP/853 here; dnscrypt-proxy will fail-over to DoH on 443.
  # AGH labels queries with ClientID "razorback" via the DoH path / DoT SNI.
  services.encryptedDns = {
    enable = true;
    dohStamp = "sdns://AgcAAAAAAAAADTE1Mi43MC42OS4yMzUAFnJhem9yYmFjay5qYWdhZGFtOTcudWsUL2Rucy1xdWVyeS9yYXpvcmJhY2s";
    dotStamp = "sdns://AwcAAAAAAAAADTE1Mi43MC42OS4yMzUAFnJhem9yYmFjay5qYWdhZGFtOTcudWs";
    rawDotFallback = "152.70.69.235#razorback.jagadam97.uk";
  };

  # Kernel networking tweaks
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 0;
    "net.ipv4.ip_forward" = 1;
    # ISP advertises an IPv6 default route but never hands out a global
    # prefix, so every AAAA connection wastes ~5s on a SYN timeout before
    # falling back to v4. Disable v6 until the upstream is fixed.
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
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
