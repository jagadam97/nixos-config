# Kayda - Laptop homelab server (Intel i5-8300H + GTX 1050 Ti Mobile)
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/services/encrypted-dns.nix
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
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXs8gealQWXMlEN++Ew7V4EqUFf7Cd+Pnr06ZqtYtdO+SYmA4fdmc9qz5/GI2JJnzs0+sHak4ZCtUihYWN3raeFy/zubKDcycZI44Lcy5SjJhfprg/c/XAags3GuZEnzhlXuqS6Uzeljgps+6gx7eiSHM/tFFV2T3kOoisq0z7kDqsi6Aq1tblMoHyvvUBPjO1huRiqcECrNFA4SnqJMVtspvIpLN74O568NDkc40ZQtcDbdbjZgfRpXx+xVWwO4gGwbrqrAZ8llItrQsGtmC6WoH8c+CUMguJqn7T4cb9nzvbFDDQLKga3DKWqZjnjwAz9lkENfPMWiZeW7kw/Yte99TCDxEm3YGfa6v/QH9JggCscSRg1Zf1UZ3VlEVXev7QvOD16DfDKeCa0z6bfvle6VUi64jVZVYAILdpGFFzrJ18L/ttZdWZYwKIXp18lcWjyGWJDsY6OcdR3XGtI5k4ey8UVa384V5pl36bP1KpD0VN6oAvHWszluHdVpZR4Gk= dines@Optimus"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIg3tJuOvpBMqDvBjBrq5KxkE5ZiK/Dlr28uSSm1mx7U"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHMJ9s1gDUT9aJaLTGDH4gdXAXjbfoBHJYLd9aSxI9qQ jagadam97@razorback"
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
  # Encrypted DNS via dnscrypt-proxy → AGH on beast.jagadam97.uk.
  # AGH labels queries with ClientID "kayda" via the DoH path / DoT SNI.
  services.encryptedDns = {
    enable = true;
    dohStamp = "sdns://AgcAAAAAAAAADTE1Mi43MC42OS4yMzUAEmtheWRhLmphZ2FkYW05Ny51axAvZG5zLXF1ZXJ5L2theWRh";
    dotStamp = "sdns://AwcAAAAAAAAADTE1Mi43MC42OS4yMzUAEmtheWRhLmphZ2FkYW05Ny51aw";
    rawDotFallback = "152.70.69.235#kayda.jagadam97.uk";
  };

  # Firewall
  networking.firewall.enable = false;

  # Timezone
  time.timeZone = "Asia/Kolkata";

  # Leave nix.settings.extra-platforms at its default so i686-linux is included
  # (needed for 32-bit NVIDIA libs via hardware.graphics.enable32Bit).
  # nix.settings.extra-platforms = lib.mkForce [];

  # System state version
  system.stateVersion = "26.11";

  # SOPS configuration for this host
  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
}
