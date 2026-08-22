# pella - Raspberry Pi 4 router (phase 1: NixOS only, no routing yet)
#
# Phase 1 scope is deliberately narrow: boot NixOS, static networking, stay
# reachable. The WAN/LAN/PPPoE/nftables work is phase 2 - see
# docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    # sd-image-aarch64 owns the partition layout, the FAT32 firmware partition
    # and its contents (bootcode.bin, start4.elf, u-boot.bin, armstub8-gic.bin,
    # config.txt). It uses an MBR table, which is what Debian booted from on
    # this Pi, and it defines fileSystems for / and /boot/firmware by label.
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    ./hardware.nix
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

  # Interface names are pinned by MAC. The static address above is bound to
  # eth0, and this host is installed and administered without physical access:
  # if the onboard NIC ever came up under a different name there would be no
  # way back in. d8:3a:dd:24:76:1e is the onboard bcmgenet, 5c:62:8b:25:de:73
  # the TP-Link UE300 that becomes the phase 2 WAN.
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="d8:3a:dd:24:76:1e", NAME="eth0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="5c:62:8b:25:de:73", NAME="eth1"
  '';

  # Remote recovery guard.
  #
  # NixOS boots from the USB disk while Debian stays untouched on the microSD,
  # with the EEPROM boot order set to USB first, microSD second. The firmware
  # only falls back to the card when the USB disk fails to boot at all - a boot
  # that reaches userspace but is unreachable over the network would strand the
  # box, and there is no console on it.
  #
  # So unless a boot is confirmed within 20 minutes, take start4.elf off the USB
  # firmware partition and reboot: the firmware can then no longer boot the USB
  # disk and falls through to Debian, which is reachable.
  #
  #   confirm:  sudo touch /var/lib/pella-boot-confirmed
  #   re-arm:   sudo rm /var/lib/pella-boot-confirmed
  #   undo a trip, from Debian: mount the USB FAT partition and rename
  #             start4.elf.disabled back to start4.elf
  systemd.services.pella-boot-guard = {
    description = "Fall back to microSD boot unless this boot was confirmed";
    path = [
      pkgs.util-linux
      pkgs.coreutils
      pkgs.systemd
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -e /var/lib/pella-boot-confirmed ]; then
        echo "boot confirmed, leaving USB boot in place"
        exit 0
      fi
      echo "boot not confirmed - disabling USB boot so the firmware falls back to the microSD"

      # /boot/firmware is nofail,noauto, and the image does not ship the mount
      # point, so create it before mounting.
      mkdir -p /boot/firmware
      if ! mount /boot/firmware; then
        echo "could not mount the firmware partition - staying up instead of rebooting"
        exit 1
      fi

      if [ -e /boot/firmware/start4.elf ]; then
        mv /boot/firmware/start4.elf /boot/firmware/start4.elf.disabled
      fi
      sync
      # Only reboot once USB boot is provably disabled. Rebooting on a failed
      # rename would just boot this system again and loop every OnBootSec.
      if [ -e /boot/firmware/start4.elf ] || [ ! -e /boot/firmware/start4.elf.disabled ]; then
        echo "start4.elf is still in place - staying up instead of rebooting into a loop"
        umount /boot/firmware || true
        exit 1
      fi
      umount /boot/firmware || true
      systemctl reboot
    '';
  };

  systemd.timers.pella-boot-guard = {
    description = "Arm the microSD fallback 20 minutes into each boot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20min";
      AccuracySec = "5s";
      Unit = "pella-boot-guard.service";
    };
  };
}
