# pella - Raspberry Pi 4 router (phase 1: NixOS only, no routing yet)
#
# Phase 1 scope is deliberately narrow: boot NixOS, static networking, stay
# reachable. The WAN/LAN/PPPoE/nftables work is phase 2 - see
# docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./firmware.nix
  ];

  networking.hostName = "pella";

  users.users.jagadam97 = {
    isNormalUser = true;
    description = "jagadam97";
    hashedPassword = "$6$BdzCOxfkibSHCtcR$OQ3XWbqj3QXkvwdYuUWo/yWOypBNGJOX0eBcElD7MDxoTNpqf01mYM8bf5K6HfzorhL5.RYnVZ6lD1atMlda01";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII0PaRuEIaOKCyD0C/MNT00ZSjCFC+K2LpNzMIDOacd2 dinesh.reddy@macbook"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXs8gealQWXMlEN++Ew7V4EqUFf7Cd+Pnr06ZqtYtdO+SYmA4fdmc9qz5/GI2JJnzs0+sHak4ZCtUihYWN3raeFy/zubKDcycZI44Lcy5SjJhfprg/c/XAags3GuZEnzhlXuqS6Uzeljgps+6gx7eiSHM/tFFV2T3kOoisq0z7kDqsi6Aq1tblMoHyvvUBPjO1huRiqcECrNFA4SnqJMVtspvIpLN74O568NDkc40ZQtcDbdbjZgfRpXx+xVWwO4gGwbrqrAZ8llItrQsGtmC6WoH8c+CUMguJqn7T4cb9nzvbFDDQLKga3DKWqZjnjwAz9lkENfPMWiZeW7kw/Yte99TCDxEm3YGfa6v/QH9JggCscSRg1Zf1UZ3VlEVXev7QvOD16DfDKeCa0z6bfvle6VUi64jVZVYAILdpGFFzrJ18L/ttZdWZYwKIXp18lcWjyGWJDsY6OcdR3XGtI5k4ey8UVa384V5pl36bP1KpD0VN6oAvHWszluHdVpZR4Gk= dines@Optimus"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIg3tJuOvpBMqDvBjBrq5KxkE5ZiK/Dlr28uSSm1mx7U"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHMJ9s1gDUT9aJaLTGDH4gdXAXjbfoBHJYLd9aSxI9qQ jagadam97@razorback"
    ];
    linger = true;
  };

  # Static addressing, no DHCP client. This is the address Debian holds today,
  # so nothing else on the LAN has to change. Gateway is still the ONT in
  # phase 1; pella takes over .1 in phase 2.
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "192.168.4.230";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "192.168.4.1";
  networking.nameservers = [ "192.168.4.1" ];

  # eth1 is the TP-Link UE300 (RTL8153, MAC 5c:62:8b:25:de:73). Left
  # unconfigured on purpose - it becomes the PPPoE WAN in phase 2.

  # modules/common/ssh.nix enables password auth for every host that is not
  # kayda. Not acceptable on a future gateway.
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;
  services.openssh.settings.KbdInteractiveAuthentication = lib.mkForce false;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  time.timeZone = "Asia/Kolkata";

  # modules/common/nix-settings.nix advertises i686-linux, which is meaningful
  # on the x86_64 hosts and false on this one.
  nix.settings.extra-platforms = lib.mkForce [ ];

  system.stateVersion = "26.11";

  # No secrets are used in phase 1. The age key derives from this host's SSH
  # host key, which does not exist until first boot, so .sops.yaml and a real
  # secrets.yaml come after the box is up - before phase 2, which needs PPPoE
  # credentials stored.
  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
}
