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
      # kayda drives deploys: it builds aarch64 under binfmt and pushes the
      # closure. deploy-rs itself connects as root, but nix-copy-closure and
      # any hands-on debugging go through this account.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG9OYOCMFtM/x8dtUp/FamUELYhmmVfvqkh+7Kla3DvR kayda@nixos"
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

  # eth1 is the TP-Link UE300 (RTL8153, MAC 5c:62:8b:25:de:73). It was going to
  # be the PPPoE WAN, but the ASUS RT-AC88U owns the network edge now, so it
  # stays down and unconfigured. Its name is still pinned by MAC below in case
  # it is ever used.

  # modules/common/ssh.nix enables password auth for every host that is not
  # kayda. Not acceptable on a future gateway.
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;
  services.openssh.settings.KbdInteractiveAuthentication = lib.mkForce false;

  # Key-only root, for deploy-rs pushes from kayda.
  #
  # modules/common/ssh.nix sets PermitRootLogin = "no" for the whole fleet. This
  # host is the exception because deploys have to run unattended: activation is
  # root's job, and magic rollback needs the deployer to reconnect on its own
  # within confirmTimeout, so there is nobody to type a sudo password. Password
  # auth stays force-disabled above, so this is key-only.
  #
  # The key below is kayda's deploy key, not an interactive login key. Whichever
  # account on kayda holds the private half is the one that must run `deploy`.
  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG9OYOCMFtM/x8dtUp/FamUELYhmmVfvqkh+7Kla3DvR kayda@nixos"
  ];

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  time.timeZone = "Asia/Kolkata";

  # modules/common/nix-settings.nix advertises i686-linux, which is meaningful
  # on the x86_64 hosts and false on this one.
  nix.settings.extra-platforms = lib.mkForce [ ];

  environment.systemPackages = with pkgs; [ lm_sensors ];

  # Disk health monitoring is wired but off. The only attached disk is the USB
  # stick this system boots from, and SMART passthrough over a USB bridge is
  # unreliable - a unit that always fails just teaches you to ignore it. Turn
  # this on when the root moves to the Samsung EVO SSD.
  services.smartd.enable = false;

  # Debian wrote to the LAN InfluxDB, bucket "pi" - keep the same target so
  # existing dashboards keep working. Its Loki output is not carried over: it
  # still pointed at an unedited grafana.net placeholder URL.
  services.telegrafMetrics = {
    influxUrls = [ "http://192.168.4.248:8086" ];
    organization = "oracle";
    bucket = "pi";
    # Pi thermals. wireless is not carried over - wlan0 is unused.
    extraInputs.temp = [ { } ];
  };

  # The shared disk input does not ignore NFS, and the Proxmox mounts are hard
  # mounts. If 192.168.4.240 goes away, telegraf blocks stat'ing /mnt/* and the
  # whole agent stalls, so skip network filesystems here.
  services.telegraf.extraConfig.inputs.disk = lib.mkForce [
    {
      ignore_fs = [
        "tmpfs"
        "devtmpfs"
        "devfs"
        "overlay"
        "squashfs"
        "nfs"
        "nfs4"
      ];
    }
  ];

  # The scraper reads its qBittorrent and InfluxDB credentials from one env
  # file, so the whole file is the secret rather than individual keys.
  sops.secrets."homelab-scrapper.env" = {
    owner = "homelab-scrapper";
    group = "homelab-scrapper";
    restartUnits = [ "homelab-scrapper.service" ];
  };

  services.homelabScrapper = {
    enable = true;
    environmentFile = config.sops.secrets."homelab-scrapper.env".path;
  };

  system.stateVersion = "26.11";

  # No secrets are used in phase 1. The age key derives from this host's SSH
  # host key, which does not exist until first boot, so .sops.yaml and a real
  # secrets.yaml come after the box is up - before phase 2, which needs PPPoE
  # credentials stored.
  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  # Interface names are pinned by MAC. The static address above is bound to
  # eth0, and this host is installed and administered without physical access:
  # if the onboard NIC ever came up under a different name there would be no
  # way back in. d8:3a:dd:24:76:1e is the onboard bcmgenet, 5c:62:8b:25:de:73
  # the TP-Link UE300 that becomes the phase 2 WAN.
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="d8:3a:dd:24:76:1e", NAME="eth0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="5c:62:8b:25:de:73", NAME="eth1"
  '';

  # The microSD fallback guard that used to live here is gone with the move of
  # the root to the microSD itself. It renamed start4.elf on the boot device's
  # firmware partition whenever a boot went unconfirmed, so that the firmware
  # fell through to Debian on the card. Now that the card *is* the root there is
  # nothing behind it to fall through to: the rename would only make this host
  # unbootable. The SanDisk USB disk is the recovery medium instead - it is not
  # attached during normal boots, because it carries the same NIXOS_SD and
  # FIRMWARE labels and root is mounted by label.
}
