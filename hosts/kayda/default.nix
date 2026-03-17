# Kayda - Laptop homelab server (Intel i5-8300H + GTX 1050 Ti Mobile)
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
  ];

  # Hostname
  networking.hostName = "kayda";

  # User configuration
  users.users.jagadam97 = {
    isNormalUser = true;
    description = "jagadam97";
    hashedPassword = "$6$BdzCOxfkibSHCtcR$OQ3XWbqj3QXkvwdYuUWo/yWOypBNGJOX0eBcElD7MDxoTNpqf01mYM8bf5K6HfzorhL5.RYnVZ6lD1atMlda01";
    extraGroups = [ "networkmanager" "wheel" "video" "render" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII0PaRuEIaOKCyD0C/MNT00ZSjCFC+K2LpNzMIDOacd2 dinesh.reddy@macbook"
    ];
    linger = true;
  };

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking - static IP via NetworkManager
  # Interface: enp3s0 (confirmed via ip a on Ubuntu)
  networking.networkmanager.enable = true;
  networking.interfaces.enp3s0.ipv4.addresses = [{
    address = "192.168.4.200";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.4.1";
  networking.nameservers = [
    "152.70.69.235"  # beast.jagadam97.uk - primary DNS
    "1.1.1.1"        # Cloudflare fallback
    "8.8.8.8"        # Google fallback
  ];
  services.resolved.enable = true;

  # Firewall
  networking.firewall.enable = false;

  # Timezone
  time.timeZone = "Asia/Kolkata";

  # System state version
  system.stateVersion = "26.05";

  # SOPS configuration for this host
  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
}
