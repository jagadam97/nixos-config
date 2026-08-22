# pella — NixOS on Raspberry Pi 4 (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a new `aarch64-linux` NixOS host `pella` on the Raspberry Pi 4, replacing Raspberry Pi OS, with static networking and no DHCP client, managed from this repo.

**Architecture:** Two flake outputs. `pella-installer` is a throwaway `sd-image-aarch64` written to a pendrive, used to boot the Pi headlessly. `pella` is the real system: `disko`-managed microSD with a FAT32 firmware partition, a separate ext4 `/boot` (so u-boot never has to parse btrfs), and a btrfs root with the same subvolume set as the x86 hosts. A custom activation script populates `/boot/firmware` with Raspberry Pi firmware and u-boot, replicating what `sdImage.populateFirmwareCommands` does — `nixos-hardware` does not do this.

**Tech Stack:** nixpkgs unstable, flakes, `nixos-hardware` (new input), `disko`, `sops-nix` (wired but unused in phase 1), btrfs, u-boot + extlinux, Tailscale.

**Spec:** `docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md`

---

## Note on verification style

This repo has no unit test suite; it is a Nix flake. The TDD analogue used
throughout is: **run the evaluation or build command, confirm it fails for the
expected reason, make the change, confirm it now succeeds.** Every task below
gives the exact command and the expected output on both sides.

Builds for `aarch64-linux` are emulated via `qemu-aarch64` binfmt on alienX
(x86_64, 32 cores). `builders-use-substitutes = true` is already set, so most of
the closure arrives prebuilt from `cache.nixos.org`.

## File structure

| File | Responsibility |
|---|---|
| `flake.nix` | Modify: add `nixos-hardware` input; add `pella` and `pella-installer` outputs |
| `hosts/pella/disko.nix` | Create: three-partition microSD layout, btrfs subvolumes |
| `hosts/pella/firmware.nix` | Create: populate `/boot/firmware` with RPi firmware + u-boot + config.txt |
| `hosts/pella/hardware.nix` | Create: platform, initrd modules, zram, boot loader |
| `hosts/pella/default.nix` | Create: hostname, user, static networking, timezone, sops stub |
| `hosts/pella/installer.nix` | Create: throwaway sd-image with keys and static IP baked in |

`firmware.nix` is deliberately its own file rather than folded into
`hardware.nix`: it is the least certain part of this design and the most likely
to need iteration, so it should be readable and replaceable on its own.

---

### Task 1: Add the `nixos-hardware` flake input

**Files:**
- Modify: `flake.nix:4-30` (the `inputs` block)

- [ ] **Step 1: Confirm the input is currently absent**

Run:
```bash
nix flake metadata --json 2>/dev/null | grep -c nixos-hardware || echo "absent"
```
Expected: `0` or `absent`.

- [ ] **Step 2: Add the input**

In `flake.nix`, inside `inputs`, after the `disko` block, add:

```nix
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
```

- [ ] **Step 3: Add it to the outputs argument list**

In `flake.nix`, the `outputs` function destructures its inputs. Add
`nixos-hardware,` to that list, after `disko,`:

```nix
  outputs =
    {
      self,
      nixpkgs,
      darwin,
      home-manager,
      sops-nix,
      disko,
      nixos-hardware,
      nix-index-database,
      nixpkgs-jellyfin,
      ...
    }@inputs:
```

- [ ] **Step 4: Verify the flake still evaluates and the lock updates**

Run:
```bash
nix flake lock && nix flake metadata --json | python3 -c "import json,sys; print('nixos-hardware' in json.load(sys.stdin)['locks']['nodes'])"
```
Expected: `True`

- [ ] **Step 5: Verify no existing host broke**

Run:
```bash
nix eval .#nixosConfigurations.kayda.config.system.build.toplevel.drvPath
```
Expected: a `/nix/store/...drv` path, no error.

- [ ] **Step 6: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat(pella): add nixos-hardware flake input

Needed for the raspberry-pi-4 module, which sets the RPi4 kernel, the
device-tree filter and the extlinux boot path."
```

---

### Task 2: Create the disk layout

**Files:**
- Create: `hosts/pella/disko.nix`

- [ ] **Step 1: Create the file**

```nix
# Disk layout for pella - internal microSD (/dev/mmcblk0, 29.8GB Samsung EB1QT)
#
# Three partitions, unlike the two used on the x86 hosts:
#   p1  /boot/firmware  FAT32  RPi firmware blobs + u-boot, read by the SoC
#   p2  /boot           ext4   extlinux.conf + kernels, read by u-boot
#   p3  /               btrfs  subvolumes
#
# /boot is a separate ext4 partition on purpose. u-boot has to read
# extlinux.conf, and its btrfs support is read-only and unreliable with
# subvolumes - putting /boot on btrfs risks a Pi that does not boot at all.
{ ... }:

let
  # zstd:3 rather than the x86 hosts' zstd:6 - four Cortex-A72 cores will be
  # competing with PPPoE softirq load once this box is the router.
  # No "ssd": that is an allocation hint for real SSDs, meaningless on microSD.
  # discard=async: the card reports discard_granularity=4194304 and
  # discard_max_bytes=170519429120, and async keeps trims off the write path
  # (synchronous discard can stall writes badly on SD).
  btrfsMountOptions = [
    "compress=zstd:3"
    "noatime"
    "discard=async"
  ];
in
{
  disko.devices = {
    disk = {
      sd = {
        type = "disk";
        device = "/dev/mmcblk0";
        content = {
          type = "gpt";
          partitions = {
            # priority is load-bearing: without it disko orders partitions by
            # attribute name alphabetically, which would put "boot" before
            # "firmware" and hand the SoC the wrong first partition.
            firmware = {
              priority = 1;
              size = "512M";
              type = "0700";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            boot = {
              priority = 2;
              size = "1G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            root = {
              priority = 3;
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = btrfsMountOptions;
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = btrfsMountOptions;
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = btrfsMountOptions;
                  };
                  "@varlib" = {
                    mountpoint = "/var/lib";
                    mountOptions = btrfsMountOptions;
                  };
                  "@log" = {
                    mountpoint = "/var/log";
                    mountOptions = btrfsMountOptions;
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
```

- [ ] **Step 2: Verify it parses**

Run:
```bash
nix-instantiate --parse hosts/pella/disko.nix > /dev/null && echo PARSE_OK
```
Expected: `PARSE_OK`

- [ ] **Step 3: Commit**

```bash
git add hosts/pella/disko.nix
git commit -m "feat(pella): add disko layout for the internal microSD

Three partitions rather than the x86 hosts' two. /boot gets its own ext4
partition because u-boot must read extlinux.conf and its btrfs support is
unreliable with subvolumes.

btrfs tuned for the medium: zstd:3 to leave CPU headroom for PPPoE softirq
load later, ssd dropped as meaningless on microSD, discard=async added
since the card reports discard support."
```

---

### Task 3: Populate the Raspberry Pi firmware partition

This is the task that makes the difference between a booting Pi and a black
screen. `nixos-hardware`'s `raspberry-pi-4` module sets the extlinux boot path
but explicitly does **not** manage the firmware partition or `config.txt`.
`sdImage` does it via `populateFirmwareCommands`; a `disko` install has no
equivalent, so we replicate it as an activation script.

The file list and `config.txt` contents below are taken from
`nixos/modules/installer/sd-card/sd-image-aarch64.nix` in nixpkgs, reduced to
the Pi 4 files only.

**Files:**
- Create: `hosts/pella/firmware.nix`

- [ ] **Step 1: Create the file**

```nix
# Populate /boot/firmware for the Raspberry Pi 4.
#
# The SoC bootloader reads the FAT32 firmware partition, loads u-boot, and
# u-boot then reads /boot/extlinux/extlinux.conf from the ext4 /boot partition.
#
# nixos-hardware's raspberry-pi-4 module sets up the extlinux side but does not
# touch the firmware partition. sd-image-aarch64.nix does this via
# sdImage.populateFirmwareCommands, which a disko install never runs - so we do
# it here on every activation instead. That also means firmware and u-boot track
# nixpkgs across rebuilds rather than drifting from whatever was installed once.
{ config, lib, pkgs, ... }:

let
  configTxt = pkgs.writeText "config.txt" ''
    kernel=u-boot.bin

    # Boot in 64-bit mode.
    arm_64bit=1

    # U-Boot needs this regardless of whether UART is actually used.
    enable_uart=1

    # Stop the firmware smashing the framebuffer set up by the mainline kernel
    # when it wants to show low-voltage or overtemperature warnings.
    avoid_warnings=1

    [pi4]
    enable_gic=1
    armstub=armstub8-gic.bin
    disable_overscan=1
    arm_boost=1
  '';

  # Pi 4 only. The upstream sd-image ships Pi 3 and Pi 5 files too; this host is
  # a Pi 4B Rev 1.5 and carrying the rest would just be noise on a 512M partition.
  firmware = pkgs.runCommand "pella-rpi-firmware" { } ''
    mkdir -p $out
    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bootcode.bin $out/
    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/fixup*.dat $out/
    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/start*.elf $out/
    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb $out/
    cp ${pkgs.ubootRaspberryPiAarch64}/u-boot.bin $out/u-boot.bin
    cp ${pkgs.raspberrypi-armstubs}/armstub8-gic.bin $out/armstub8-gic.bin
    cp ${configTxt} $out/config.txt
  '';
in
{
  # rsync with -rt rather than -a: the target is vfat, which has no concept of
  # ownership or unix permissions, so -a produces a stream of warnings and
  # spurious diffs on every run.
  system.activationScripts.pellaRpiFirmware = {
    text = ''
      stamp=/boot/firmware/.pella-firmware
      if [ ! -e "$stamp" ] || [ "$(cat "$stamp")" != "${firmware}" ]; then
        echo "pella: populating /boot/firmware from ${firmware}"
        ${pkgs.rsync}/bin/rsync -rt --delete \
          --exclude='.pella-firmware' \
          ${firmware}/ /boot/firmware/
        echo "${firmware}" > "$stamp"
      fi
    '';
  };

  # rsync is only needed by the activation script above, but having it on PATH
  # makes debugging the firmware partition by hand much easier.
  environment.systemPackages = [ pkgs.rsync ];
}
```

- [ ] **Step 2: Verify it parses**

Run:
```bash
nix-instantiate --parse hosts/pella/firmware.nix > /dev/null && echo PARSE_OK
```
Expected: `PARSE_OK`

- [ ] **Step 3: Commit**

```bash
git add hosts/pella/firmware.nix
git commit -m "feat(pella): populate /boot/firmware with RPi firmware and u-boot

nixos-hardware's raspberry-pi-4 module sets up extlinux but does not touch
the firmware partition, and disko installs never run
sdImage.populateFirmwareCommands. Without this the SoC has nothing to load
and the Pi boots to a black screen.

File list and config.txt are lifted from nixpkgs'
sd-image-aarch64.nix, reduced to the Pi 4 files. Runs on every activation
so firmware and u-boot track nixpkgs instead of drifting."
```

---

### Task 4: Create the hardware configuration

**Files:**
- Create: `hosts/pella/hardware.nix`

- [ ] **Step 1: Create the file**

```nix
# Hardware configuration for pella - Raspberry Pi 4 Model B Rev 1.5 (4GB)
# Board revision c03115. Bootloader EEPROM 2026/05/17, VL805 fw 000138c0.
#
# The boot loader itself (grub off, generic-extlinux-compatible on), the RPi4
# kernel and the device-tree filter all come from nixos-hardware's
# raspberry-pi-4 module, wired in flake.nix. Firmware partition contents come
# from ./firmware.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # mmc_block for the internal microSD; the usb/xhci set so a USB-attached root
  # stays possible without an initrd rebuild (a USB SSD is the intended
  # long-term medium for this host).
  boot.initrd.availableKernelModules = [
    "mmc_block"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "uas"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.supportedFilesystems = [
    "btrfs"
    "vfat"
    "ext4"
  ];

  # HDMI console only. The upstream sd-image also sets ttyS0/ttyAMA0 for boards
  # with serial headers; this Pi is managed over the network and Debian ran with
  # 8250.nr_uarts=0 anyway.
  boot.kernelParams = [ "console=tty1" ];

  # Disko owns fileSystems - see ./disko.nix
  swapDevices = [ ];

  # 4GB board that will be running nixos-rebuild. Debian ran 2GB of zram here,
  # which is worth keeping.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  hardware.enableRedistributableFirmware = true;
}
```

- [ ] **Step 2: Verify it parses**

Run:
```bash
nix-instantiate --parse hosts/pella/hardware.nix > /dev/null && echo PARSE_OK
```
Expected: `PARSE_OK`

- [ ] **Step 3: Commit**

```bash
git add hosts/pella/hardware.nix
git commit -m "feat(pella): add hardware config for the Pi 4

aarch64 platform, initrd modules for the internal microSD plus USB/uas so a
USB root stays possible later, and zram to match what Debian ran on this
4GB board."
```

---

### Task 5: Create the host configuration

**Files:**
- Create: `hosts/pella/default.nix`

Two things worth knowing before writing this file:

1. `modules/common/ssh.nix` computes `PasswordAuthentication = !isKayda`, where
   `isKayda` is a hostname comparison. For any host that is not `kayda` that
   evaluates to **true** — password auth enabled. That is wrong for a box
   destined to be an internet-facing gateway, so this host overrides it with
   `mkForce`. The shared module is left alone so no other host's behaviour changes.
2. `modules/common/nix-settings.nix:10` sets
   `extra-platforms = [ "i686-linux" "aarch64-linux" ]`. On the x86_64 hosts that
   enables emulated aarch64 builds. On an aarch64 host it advertises an
   `i686-linux` capability the Pi does not have, so it is overridden here.

- [ ] **Step 1: Create the file**

```nix
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
  # host key, which does not exist until first boot, so .sops.yaml and
  # hosts/pella/secrets.yaml come after the box is up - before phase 2, which
  # needs PPPoE credentials stored.
  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
}
```

- [ ] **Step 2: Create a placeholder secrets file so the sops options resolve**

`sops.defaultSopsFile` points at a path that must exist at evaluation time.

Run:
```bash
printf '{}\n' > hosts/pella/secrets.yaml
```

- [ ] **Step 3: Verify it parses**

Run:
```bash
nix-instantiate --parse hosts/pella/default.nix > /dev/null && echo PARSE_OK
```
Expected: `PARSE_OK`

- [ ] **Step 4: Commit**

```bash
git add hosts/pella/default.nix hosts/pella/secrets.yaml
git commit -m "feat(pella): add host config

Static 192.168.4.230/24 with no DHCP client, which is the address Debian
holds today so nothing else on the LAN has to change. Gateway stays the ONT
in phase 1.

Two overrides of shared modules, both deliberate:
- modules/common/ssh.nix enables password auth for any host that is not
  kayda; forced off here since this becomes an internet-facing gateway.
- modules/common/nix-settings.nix advertises i686-linux, which is false on
  aarch64.

eth1 (the UE300) is left unconfigured - it becomes the PPPoE WAN in phase 2."
```

---

### Task 6: Wire up the `pella` flake output

**Files:**
- Modify: `flake.nix` (`nixosConfigurations` block, after the `kayda` entry)

- [ ] **Step 1: Confirm the output does not exist yet**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.networking.hostName 2>&1 | tail -1
```
Expected: an error mentioning that attribute `pella` is missing.

- [ ] **Step 2: Add the output**

In `flake.nix`, inside `nixosConfigurations`, after the closing `};` of the
`kayda` entry, add:

```nix
        # Pella - Raspberry Pi 4 router (phase 1: NixOS only, routing is phase 2)
        pella = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            nixos-hardware.nixosModules.raspberry-pi-4
            ./hosts/pella
            ./modules/common
          ];
        };
```

Note there is deliberately **no** home-manager here: it roughly doubles an
emulated aarch64 build for no phase-1 benefit and can be added later.

- [ ] **Step 3: Verify the output now evaluates**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.networking.hostName
```
Expected: `"pella"`

- [ ] **Step 4: Verify the platform and key settings resolved correctly**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.nixpkgs.hostPlatform.system
nix eval .#nixosConfigurations.pella.config.nix.settings.extra-platforms
nix eval .#nixosConfigurations.pella.config.services.openssh.settings.PasswordAuthentication
nix eval .#nixosConfigurations.pella.config.boot.loader.generic-extlinux-compatible.enable
```
Expected, in order: `"aarch64-linux"` · `[ ]` · `false` · `true`

The last one confirms `nixos-hardware`'s `raspberry-pi-4` module is actually
applying the extlinux boot path.

- [ ] **Step 5: Verify the disko layout produced the three filesystems**

Run:
```bash
nix eval --json .#nixosConfigurations.pella.config.fileSystems --apply 'fs: builtins.attrNames fs'
```
Expected: a list containing `"/"`, `"/boot"`, `"/boot/firmware"`, `"/home"`, `"/nix"`, `"/var/lib"`, `"/var/log"`

- [ ] **Step 6: Verify the btrfs mount options**

Run:
```bash
nix eval --json .#nixosConfigurations.pella.config.fileSystems."/".options
```
Expected: includes `"compress=zstd:3"`, `"noatime"`, `"discard=async"`, and **not** `"ssd"`

- [ ] **Step 7: Verify the whole system closure instantiates**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.system.build.toplevel.drvPath
```
Expected: a `/nix/store/...-nixos-system-pella-....drv` path.

This is evaluation only — nothing is built yet.

- [ ] **Step 8: Commit**

```bash
git add flake.nix
git commit -m "feat(pella): wire the pella nixosConfiguration

aarch64-linux with nixos-hardware's raspberry-pi-4 module. No home-manager:
it roughly doubles an emulated aarch64 build for no phase-1 value."
```

---

### Task 7: Create and wire the installer image

The installer exists for one reason: the Pi cannot install NixOS to the microSD
it is currently running Debian from. It boots from the pendrive instead. Its own
root is ext4 because `sdImage` cannot produce btrfs — irrelevant, since it is
discarded.

SSH keys and the static IP are baked in so the whole install is headless.

**Files:**
- Create: `hosts/pella/installer.nix`
- Modify: `flake.nix` (`nixosConfigurations` block)

- [ ] **Step 1: Create the installer config**

```nix
# Throwaway installer image for pella.
#
# Written to the SanDisk pendrive (/dev/sda), booted with BOOT_ORDER=0xf14, and
# used to disko + nixos-install onto the internal microSD. Discarded afterwards.
#
# Its root is ext4 because sdImage cannot produce btrfs. That does not matter:
# nothing here survives.
#
# SSH keys and the static IP are baked in so no keyboard or monitor is ever
# needed. Same address as Debian and as the final system - only one of the three
# ever runs at a time.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  networking.hostName = "pella-installer";

  # Uncompressed so it can be streamed straight to the pendrive with dd; the
  # default zstd image would need decompressing first.
  sdImage.compressImage = false;

  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "192.168.4.230";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "192.168.4.1";
  networking.nameservers = [ "192.168.4.1" ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Root login by key: the install runs disko and nixos-install, both of which
  # need root, and this image is thrown away immediately afterwards.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII0PaRuEIaOKCyD0C/MNT00ZSjCFC+K2LpNzMIDOacd2 dinesh.reddy@macbook"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXs8gealQWXMlEN++Ew7V4EqUFf7Cd+Pnr06ZqtYtdO+SYmA4fdmc9qz5/GI2JJnzs0+sHak4ZCtUihYWN3raeFy/zubKDcycZI44Lcy5SjJhfprg/c/XAags3GuZEnzhlXuqS6Uzeljgps+6gx7eiSHM/tFFV2T3kOoisq0z7kDqsi6Aq1tblMoHyvvUBPjO1huRiqcECrNFA4SnqJMVtspvIpLN74O568NDkc40ZQtcDbdbjZgfRpXx+xVWwO4gGwbrqrAZ8llItrQsGtmC6WoH8c+CUMguJqn7T4cb9nzvbFDDQLKga3DKWqZjnjwAz9lkENfPMWiZeW7kw/Yte99TCDxEm3YGfa6v/QH9JggCscSRg1Zf1UZ3VlEVXev7QvOD16DfDKeCa0z6bfvle6VUi64jVZVYAILdpGFFzrJ18L/ttZdWZYwKIXp18lcWjyGWJDsY6OcdR3XGtI5k4ey8UVa384V5pl36bP1KpD0VN6oAvHWszluHdVpZR4Gk= dines@Optimus"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIg3tJuOvpBMqDvBjBrq5KxkE5ZiK/Dlr28uSSm1mx7U"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHMJ9s1gDUT9aJaLTGDH4gdXAXjbfoBHJYLd9aSxI9qQ jagadam97@razorback"
  ];

  # Everything the install needs. sd-image-aarch64 is not an installer profile,
  # so nixos-install-tools is not present by default.
  environment.systemPackages = with pkgs; [
    nixos-install-tools
    btrfs-progs
    dosfstools
    e2fsprogs
    gptfdisk
    parted
    rsync
    git
    tmux
  ];

  # The installer builds nothing itself - it receives a prebuilt closure copied
  # from alienX - but flakes must be enabled for nixos-install --flake to work
  # if we ever fall back to that.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # nixos-install writes the whole closure to /mnt; the default sd-image tmpfs
  # sizing is not the constraint, but this keeps builds off RAM on a 4GB board.
  nix.settings.max-jobs = 2;

  system.stateVersion = "26.11";
}
```

- [ ] **Step 2: Add the flake output**

In `flake.nix`, inside `nixosConfigurations`, after the `pella` entry:

```nix
        # Throwaway installer image for pella, written to the pendrive.
        pella-installer = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/pella/installer.nix
          ];
        };
```

Note `nixos-hardware` is deliberately not imported here — `sd-image-aarch64.nix`
already sets up its own boot path, and adding the RPi4 module on top risks a
conflicting kernel choice in an image whose only job is to boot once.

- [ ] **Step 3: Verify the installer output evaluates**

Run:
```bash
nix eval .#nixosConfigurations.pella-installer.config.networking.hostName
nix eval .#nixosConfigurations.pella-installer.config.sdImage.compressImage
```
Expected: `"pella-installer"` then `false`

- [ ] **Step 4: Verify the image derivation instantiates**

Run:
```bash
nix eval .#nixosConfigurations.pella-installer.config.system.build.sdImage.drvPath
```
Expected: a `/nix/store/...-nixos-sd-image-....img.drv` path.

- [ ] **Step 5: Commit**

```bash
git add hosts/pella/installer.nix flake.nix
git commit -m "feat(pella): add throwaway installer image

The Pi cannot install to the microSD it is running Debian from, so it boots
this from the pendrive instead. SSH keys and the static IP are baked in so
the whole install is headless.

Uncompressed image so it can be dd'd straight to the pendrive, and
nixos-install-tools included since sd-image-aarch64 is not an installer
profile."
```

---

### Task 8: Build both images on alienX

**Files:** none — this is a build and verification task.

- [ ] **Step 1: Confirm alienX is reachable and advertises aarch64**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net 'uname -m; ls /proc/sys/fs/binfmt_misc/ | grep qemu-aarch64'
```
Expected: `x86_64` then `qemu-aarch64`.

The build is emulated. That is expected and acceptable — `aarch64-linux` has
full `cache.nixos.org` coverage and `builders-use-substitutes` is already on, so
only uncached derivations get emulated.

- [ ] **Step 2: Build the installer image**

Run:
```bash
nix build .#nixosConfigurations.pella-installer.config.system.build.sdImage \
  --print-out-paths -L
```
Expected: a `/nix/store/...-nixos-sd-image-...-aarch64-linux.img/` path.

If this fails with a hash mismatch or a `qemu` segfault on a specific
derivation, retry once — emulated builds occasionally fault non-deterministically.

- [ ] **Step 3: Record the image path and size**

Run:
```bash
IMG=$(find "$(nix build .#nixosConfigurations.pella-installer.config.system.build.sdImage --print-out-paths)" -name '*.img' | head -1)
echo "$IMG"; ls -lh "$IMG"
```
Expected: a path ending `.img` and a size in the low single-digit GB.

- [ ] **Step 4: Build the real system closure**

Run:
```bash
nix build .#nixosConfigurations.pella.config.system.build.toplevel \
  --print-out-paths -L
```
Expected: a `/nix/store/...-nixos-system-pella-...` path.

This is the closure that gets copied to the installer in Task 11 — building it
now means the destructive step later is not also the first time this config has
ever been compiled.

- [ ] **Step 5: Verify the firmware derivation built and contains what it should**

Run:
```bash
FW=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.pella.config.system.activationScripts.pellaRpiFirmware.text 2>/dev/null) || \
FW=$(nix eval --raw .#nixosConfigurations.pella.config.system.activationScripts.pellaRpiFirmware.text \
  | grep -oE '/nix/store/[a-z0-9]{32}-pella-rpi-firmware' | head -1)
echo "firmware derivation: $FW"
nix build --no-link "$FW"
ls "$FW"
```
Expected: `armstub8-gic.bin`, `bcm2711-rpi-4-b.dtb`, `bootcode.bin`, `config.txt`, `fixup*.dat`, `start*.elf`, `u-boot.bin`

If `u-boot.bin` or `armstub8-gic.bin` is missing, the Pi will not boot. Stop and
fix Task 3 before going any further.

- [ ] **Step 6: Commit nothing, but record the paths**

Write both store paths into the plan checklist or a scratch note. They are needed
in Tasks 9 and 11.

---

### Task 9: Write the installer to the pendrive

> **Destructive step.** This overwrites `/dev/sda`, the SanDisk pendrive
> (`0781:55a9`, 114.6GB), which currently holds an installer ISO (an 807MB
> partition, an 8.3MB EFI partition and a 300K partition). That content will be
> destroyed. The internal microSD `/dev/mmcblk0` is **not** touched by this task
> and Debian keeps running.

**Files:** none.

- [ ] **Step 1: Confirm the target device is the pendrive and not the microSD**

Run:
```bash
ssh pi@192.168.4.230 'lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,SERIAL /dev/sda'
```
Expected: `sda 114.6G disk usb SanDisk 3.2Gen1 00022511072824223236`

If this shows anything other than the 114.6G SanDisk, **stop**. Do not proceed
on a guessed device name.

- [ ] **Step 2: Confirm nothing on the pendrive is mounted**

Run:
```bash
ssh pi@192.168.4.230 'findmnt -n -o TARGET,SOURCE | grep /dev/sda || echo "not mounted"'
```
Expected: `not mounted`

If anything is mounted, unmount it first: `sudo umount /dev/sda?`

- [ ] **Step 3: Stream the image to the pendrive**

Run from the machine holding the built image:
```bash
IMG=$(find "$(nix build .#nixosConfigurations.pella-installer.config.system.build.sdImage --print-out-paths)" -name '*.img' | head -1)
dd if="$IMG" bs=4M status=progress | ssh pi@192.168.4.230 'sudo dd of=/dev/sda bs=4M conv=fsync status=progress'
```
Expected: `dd` progress output on both ends, ending with matching byte counts.

The pendrive measured 8.4 MB/s buffered read and writes will be slower, so budget
**10-20 minutes** for a multi-GB image. This is expected, not a hang.

- [ ] **Step 4: Flush and verify the partition table was written**

Run:
```bash
ssh pi@192.168.4.230 'sudo sync; sudo blockdev --rereadpt /dev/sda; lsblk /dev/sda; sudo fdisk -l /dev/sda | head -12'
```
Expected: `sda` now shows a small FAT firmware partition and a larger Linux
partition, and the partition table is `dos` (nixpkgs `sdImage` uses MBR).

- [ ] **Step 5: Verify the firmware partition contains a bootable payload**

Run:
```bash
ssh pi@192.168.4.230 'sudo mkdir -p /mnt/fw && sudo mount /dev/sda1 /mnt/fw && ls /mnt/fw && sudo umount /mnt/fw'
```
Expected: `bootcode.bin`, `config.txt`, `start4.elf`, `fixup4.dat`, `u-boot.bin`,
`armstub8-gic.bin`, and `bcm2711-rpi-4-b.dtb` among others.

If `u-boot.bin` is absent the Pi will not boot from this drive. Stop here.

---

### Task 10: Boot the installer and pass the validation gate

> This is the **hard stop** before anything destroys Debian. Everything up to
> here is reversible by flipping `BOOT_ORDER` back. Do not proceed to Task 11
> until every check below passes.

**Files:** none.

- [ ] **Step 1: Set the boot order to prefer USB**

Run:
```bash
ssh pi@192.168.4.230 'sudo rpi-eeprom-config > /tmp/eeprom.txt && printf "BOOT_ORDER=0xf14\n" >> /tmp/eeprom.txt && sudo rpi-eeprom-config --apply /tmp/eeprom.txt && sudo rpi-eeprom-config'
```
Expected: the printed config now contains `BOOT_ORDER=0xf14` alongside the
existing `BOOT_UART=0`, `WAKE_ON_GPIO=1`, `POWER_OFF_ON_HALT=0`.

`0xf14` reads right to left: try USB (4), then SD (1), then restart (f). Debian
on the microSD remains the fallback.

- [ ] **Step 2: Reboot**

Run:
```bash
ssh pi@192.168.4.230 'sudo reboot' || true
```
Expected: the connection drops. Wait 2-4 minutes — booting from an 8.4 MB/s
pendrive is slow.

- [ ] **Step 3: Confirm it came up as the installer, not Debian**

Run:
```bash
ssh root@192.168.4.230 'hostname; uname -a; cat /etc/os-release | head -2'
```
Expected: hostname `pella-installer`, a `#1-NixOS` kernel string, and
`NAME=NixOS`.

If you get `pi` and Debian instead, the Pi fell through to the SD card — the
pendrive did not boot. Go back to Task 9 Step 5.

- [ ] **Step 4: Confirm it is running from the pendrive and the microSD is untouched**

Run:
```bash
ssh root@192.168.4.230 'findmnt / -o SOURCE; lsblk -o NAME,SIZE,TYPE,TRAN,MOUNTPOINT'
```
Expected: `/` is on an `/dev/sda` partition, and `mmcblk0` appears with its
original 512M + 29.3G partitions, unmounted.

- [ ] **Step 5: Run the validation gate**

Run:
```bash
ssh root@192.168.4.230 '
  echo "--- addr ---";      ip -br addr show eth0
  echo "--- route ---";     ip route | head -3
  echo "--- no dhcp ---";   (pgrep -a dhcpcd || pgrep -a dhclient || echo "no dhcp client")
  echo "--- eth1 ---";      ip -br link show eth1; lsusb -t | grep r8152
  echo "--- errors ---";    journalctl -p err -b --no-pager | tail -20
'
```
Expected:
- `eth0` carries `192.168.4.230/24`
- default route via `192.168.4.1`
- `no dhcp client`
- `eth1` present, and `lsusb -t` shows `r8152` at **5000M**
- no storage or network errors in the journal

- [ ] **Step 6: Confirm outbound networking works**

Run:
```bash
ssh root@192.168.4.230 'ping -c2 -W3 1.1.1.1 && curl -sS -o /dev/null -w "%{http_code}\n" https://cache.nixos.org/nix-cache-info'
```
Expected: two ping replies and `200`.

The `200` matters specifically: Task 11 copies a closure over this path.

- [ ] **Step 7: Decision point**

If every check above passed, continue to Task 11.

If any check failed, roll back — Debian is still intact:
```bash
ssh root@192.168.4.230 'rpi-eeprom-config > /tmp/e.txt && sed -i "s/BOOT_ORDER=0xf14/BOOT_ORDER=0xf41/" /tmp/e.txt && rpi-eeprom-config --apply /tmp/e.txt && reboot'
```

---

### Task 11: Install onto the internal microSD

> **This is the destructive, irreversible step.** It wipes `/dev/mmcblk0` and
> destroys the Debian installation, including `homelab-scrapper`, `wol-server`
> and `/etc/wol-server/config.toml`, the telegraf config, and the NFS export
> setup. The user confirmed on 2026-08-22 that no backup is required.
>
> Do not run this until Task 10 passed in full.

**Files:** none.

- [ ] **Step 1: Confirm the target one final time**

Run:
```bash
ssh root@192.168.4.230 'lsblk -o NAME,SIZE,TYPE,TRAN,MOUNTPOINT /dev/mmcblk0; findmnt / -o SOURCE'
```
Expected: `mmcblk0` is 29.8G, `mmc`, **not mounted anywhere**, and `/` is on
`/dev/sda*`.

If `/` is on `mmcblk0`, you are booted from the microSD, not the pendrive. Stop.

- [ ] **Step 2: Copy the prebuilt closure to the installer**

Run from the machine that built it:
```bash
SYS=$(nix build .#nixosConfigurations.pella.config.system.build.toplevel --print-out-paths)
echo "$SYS"
nix copy --to ssh://root@192.168.4.230 "$SYS"
```
Expected: completes with no error. This avoids the Pi building its own system on
four cores.

Keep `$SYS` for Step 6.

- [ ] **Step 3: Copy this repo to the installer**

disko reads the layout from the flake, so the repo has to be present on the
installer. `--exclude .git` keeps the transfer small; no history is needed.

Run:
```bash
rsync -az --exclude .git ./ root@192.168.4.230:/tmp/nixos-config/
ssh root@192.168.4.230 'ls /tmp/nixos-config/flake.nix /tmp/nixos-config/hosts/pella/disko.nix'
```
Expected: both paths listed.

- [ ] **Step 4: Partition and format via disko**

Run:
```bash
ssh root@192.168.4.230 'cd /tmp/nixos-config && nix run github:nix-community/disko/latest -- --mode destroy,format,mount --flake .#pella'
```
Expected: disko prints each partitioning step and finishes with the filesystems
mounted under `/mnt`.

- [ ] **Step 5: Verify the layout is exactly what was designed**

Run:
```bash
ssh root@192.168.4.230 '
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT /dev/mmcblk0
  findmnt -R /mnt -o TARGET,SOURCE,FSTYPE,OPTIONS
  btrfs subvolume list /mnt
'
```
Expected:
- `mmcblk0p1` vfat 512M at `/mnt/boot/firmware`
- `mmcblk0p2` ext4 1G at `/mnt/boot`
- `mmcblk0p3` btrfs at `/mnt`, with `@root @nix @home @varlib @log` listed
- btrfs mounts show `compress=zstd:3`, `noatime`, `discard=async`

If the partition **order** is wrong (boot before firmware), the `priority`
values in `hosts/pella/disko.nix` did not apply. Fix Task 2 and redo.

- [ ] **Step 6: Install the prebuilt system**

Run, using the `$SYS` path from Step 2:
```bash
ssh root@192.168.4.230 "nixos-install --root /mnt --system $SYS --no-root-password"
```
Expected: ends with `installation finished!`.

- [ ] **Step 7: Verify the firmware partition got populated**

Run:
```bash
ssh root@192.168.4.230 'ls /mnt/boot/firmware; echo "--- extlinux ---"; ls /mnt/boot/extlinux'
```
Expected: `/mnt/boot/firmware` contains `bootcode.bin`, `config.txt`,
`start4.elf`, `fixup4.dat`, `u-boot.bin`, `armstub8-gic.bin`,
`bcm2711-rpi-4-b.dtb` and `.pella-firmware`. `/mnt/boot/extlinux` contains
`extlinux.conf`.

**This is the single most important check in the plan.** If
`/mnt/boot/firmware` is empty or missing `u-boot.bin`, the activation script from
Task 3 did not run under `nixos-install`. Populate it by hand before rebooting:

```bash
ssh root@192.168.4.230 '
  FW=$(ls -d /nix/store/*-pella-rpi-firmware | head -1)
  echo "using $FW"
  rsync -rt "$FW"/ /mnt/boot/firmware/
  echo "$FW" > /mnt/boot/firmware/.pella-firmware
  ls /mnt/boot/firmware
'
```

- [ ] **Step 8: Confirm extlinux points at a kernel that exists**

Run:
```bash
ssh root@192.168.4.230 '
  cat /mnt/boot/extlinux/extlinux.conf
  echo "--- resolving referenced files ---"
  awk "/^[[:space:]]*(LINUX|INITRD)/ {print \$2}" /mnt/boot/extlinux/extlinux.conf \
    | while read f; do ls -l "/mnt/boot/$f" 2>&1; done
'
```
Expected: every `LINUX` and `INITRD` path listed by the loop resolves to a real
file. A "No such file" here means the Pi will drop to a u-boot prompt on boot.

### Task 12: Boot from the microSD and confirm acceptance

**Files:** none.

- [ ] **Step 1: Restore SD-first boot order**

Run:
```bash
ssh root@192.168.4.230 'rpi-eeprom-config > /tmp/e.txt && sed -i "s/BOOT_ORDER=0xf14/BOOT_ORDER=0xf41/" /tmp/e.txt && rpi-eeprom-config --apply /tmp/e.txt && rpi-eeprom-config'
```
Expected: `BOOT_ORDER=0xf41`.

- [ ] **Step 2: Shut down and remove the pendrive**

Run:
```bash
ssh root@192.168.4.230 'poweroff' || true
```

Physically unplug the pendrive, then power the Pi back on.

Removing the drive rather than relying on boot order means a mistake in Step 1
cannot silently boot the installer again.

- [ ] **Step 3: Confirm it booted the real system from the microSD**

Run:
```bash
ssh jagadam97@192.168.4.230 'hostname; findmnt / -o SOURCE,FSTYPE; uname -m'
```
Expected: `pella`, `/dev/mmcblk0p3` with `btrfs`, and `aarch64`.

- [ ] **Step 4: Run the acceptance checks from the spec**

Run:
```bash
ssh jagadam97@192.168.4.230 '
  echo "--- mounts ---";    findmnt -R / -o TARGET,SOURCE,FSTYPE,OPTIONS | grep -E "btrfs|vfat|ext4"
  echo "--- subvols ---";   sudo btrfs subvolume list /
  echo "--- compress ---";  mount | grep btrfs
  echo "--- addr ---";      ip -br addr show eth0
  echo "--- no dhcp ---";   (pgrep -a dhcpcd || echo "no dhcp client")
  echo "--- eth1 ---";      lsusb -t | grep r8152
  echo "--- tailscale ---"; tailscale ip -4 || true
  echo "--- errors ---";    journalctl -p err -b --no-pager | tail -20
'
```
Expected:
- three filesystems mounted as designed, btrfs options include
  `compress=zstd:3` and `discard=async`
- five subvolumes listed
- `eth0` = `192.168.4.230/24`, no DHCP client
- `r8152` at 5000M
- a Tailscale v4 address
- no errors in the journal

- [ ] **Step 5: Bring Tailscale up if it needs authenticating**

Run:
```bash
ssh jagadam97@192.168.4.230 'sudo tailscale up --hostname pella'
```
Expected: either already-connected, or a login URL to visit once.

- [ ] **Step 6: Confirm the box can rebuild itself**

Run:
The repo was copied to `/tmp/nixos-config` in Task 11 Step 3, but `/tmp` does
not survive a reboot. Re-sync it first.

```bash
rsync -az --exclude .git ./ jagadam97@192.168.4.230:/tmp/nixos-config/
ssh jagadam97@192.168.4.230 'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella'
```
Expected: `switching to configuration...` and no error.

This is the real proof the host is self-sufficient rather than a one-shot image.

- [ ] **Step 7: Confirm the firmware activation script is idempotent**

Run:
```bash
ssh jagadam97@192.168.4.230 'sudo nixos-rebuild switch --flake /tmp/nixos-config#pella 2>&1 | grep -i "populating /boot/firmware" || echo "skipped as expected"'
```
Expected: `skipped as expected` — the stamp file should prevent a second copy.

---

### Task 13: Add the sops age key

The host SSH key only exists now that the box has booted, so this could not be
done earlier. It has to happen before phase 2, which needs PPPoE credentials.

**Files:**
- Modify: `.sops.yaml`
- Modify: `hosts/pella/secrets.yaml`

- [ ] **Step 1: Derive the age key from the new host key**

Run:
```bash
ssh jagadam97@192.168.4.230 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub' | nix run nixpkgs#ssh-to-age
```
Expected: a single `age1...` string. Record it.

- [ ] **Step 2: Add the key to `.sops.yaml`**

In the `keys:` block, after the `kayda` entry:

```yaml
  - &pella age1REPLACE_WITH_THE_KEY_FROM_STEP_1
```

And add a creation rule after the `kayda` rule:

```yaml
  - path_regex: hosts/pella/secrets\.yaml$
    key_groups:
      - age:
          - *pella
          - *admin
```

Also add `- *pella` to the `age:` list of the `secrets/common\.yaml$` rule so
this host can read shared secrets.

- [ ] **Step 3: Provision the age key file on the host**

Run:
```bash
ssh jagadam97@192.168.4.230 '
  sudo mkdir -p /var/lib/sops-nix
  sudo sh -c "cat /etc/ssh/ssh_host_ed25519_key | nix run nixpkgs#ssh-to-age -- -private-key > /var/lib/sops-nix/keys.txt"
  sudo chmod 600 /var/lib/sops-nix/keys.txt
  sudo ls -l /var/lib/sops-nix/keys.txt
'
```
Expected: a `-rw-------` file owned by root.

- [ ] **Step 4: Verify sops can round-trip a secret for this host**

Run:
```bash
printf 'placeholder: notasecret\n' > /tmp/pella-test.yaml
sops --config .sops.yaml -e /tmp/pella-test.yaml > hosts/pella/secrets.yaml
sops --config .sops.yaml -d hosts/pella/secrets.yaml
```
Expected: the decrypted output shows `placeholder: notasecret`, and
`hosts/pella/secrets.yaml` on disk is encrypted (contains `sops:` metadata and
an `age:` recipient list including the new key).

- [ ] **Step 5: Confirm the host itself can decrypt after a rebuild**

Run:
```bash
ssh jagadam97@192.168.4.230 'sudo nixos-rebuild switch --flake /tmp/nixos-config#pella && systemctl status sops-nix --no-pager | head -5'
```
Expected: the `sops-nix` unit is active/exited without failure.

- [ ] **Step 6: Commit**

```bash
git add .sops.yaml hosts/pella/secrets.yaml
git commit -m "feat(pella): add sops age key

Derived from the host SSH key, which only existed once the box had booted.
Needed before phase 2, which stores PPPoE credentials."
```

---

### Task 14: Update the spec status and finish the branch

**Files:**
- Modify: `docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md`

- [ ] **Step 1: Mark the spec done**

Change the `**Status:**` line to:

```markdown
**Status:** Implemented 2026-08-22 — see docs/superpowers/plans/2026-08-22-pella-nixos-phase1.md
```

- [ ] **Step 2: Record anything that diverged**

If the implementation departed from the design — most likely candidates are the
GPT/MBR question and the firmware activation script — add a short
`## Implementation notes` section at the end of the spec saying what changed and
why. Do not silently leave the spec describing something that was not built.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md
git commit -m "docs(pella): mark phase 1 spec implemented"
```

- [ ] **Step 4: Hand off**

Use the superpowers:finishing-a-development-branch skill to decide between
merging `feat/pella-nixos-router` to `main`, opening a PR, or leaving it.

---

## Contingencies

Things most likely to go wrong, with the concrete response. All of these are
recoverable — after Task 11 Debian is gone, but the pendrive installer remains
bootable, so a retry costs one `BOOT_ORDER` flip and a reboot.

### The Pi does not boot from the GPT-partitioned microSD

The nixpkgs `sdImage` uses an MBR table, and Debian on this Pi used MBR too
(`root=PARTUUID=88d04481-02` is MBR-style). The `disko` layout uses GPT because
disko's `table` type is deprecated and documented as breaking its own test
framework. The 2026 bootloader should read GPT, but this was not verified on
this specific board.

If the Pi will not boot from the card, boot the pendrive again
(`BOOT_ORDER=0xf14`) and switch the layout to MBR in `hosts/pella/disko.nix`:

```nix
        content = {
          type = "table";
          format = "msdos";
          partitions = [
            { name = "firmware"; start = "1M";    end = "513M"; fs-type = "fat32"; bootable = true;
              content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot/firmware"; }; }
            { name = "boot";     start = "513M";  end = "1537M"; fs-type = "ext4";
              content = { type = "filesystem"; format = "ext4"; mountpoint = "/boot"; }; }
            { name = "root";     start = "1537M"; end = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@root"   = { mountpoint = "/";        mountOptions = btrfsMountOptions; };
                  "@nix"    = { mountpoint = "/nix";     mountOptions = btrfsMountOptions; };
                  "@home"   = { mountpoint = "/home";    mountOptions = btrfsMountOptions; };
                  "@varlib" = { mountpoint = "/var/lib"; mountOptions = btrfsMountOptions; };
                  "@log"    = { mountpoint = "/var/log"; mountOptions = btrfsMountOptions; };
                };
              }; }
          ];
        };
```

Accept the deprecation warning; it is a warning, not an error.

### u-boot cannot find `extlinux.conf`

This is what the separate ext4 `/boot` exists to prevent. If it still happens,
check `/boot/extlinux/extlinux.conf` exists and its `LINUX`/`INITRD` paths
resolve. If u-boot cannot read ext4 either, fall back to `raspberry-pi-nix`
pinned via `flake.lock`, which drops u-boot entirely and has the firmware load
the kernel directly from `config.txt` — accepting an archived dependency.

### `nixos-hardware`'s RPi4 kernel conflicts with something

The module pins its own `kernelPackages`. If that collides with a module from
`modules/common`, override in `hosts/pella/hardware.nix` with
`boot.kernelPackages = lib.mkForce pkgs.linuxPackages_rpi4;`.

### The emulated build is intolerably slow

Try nauvoo instead of alienX:
```bash
nix build .#nixosConfigurations.pella.config.system.build.toplevel --builders "$NAUVOO_NIX_BUILDERS"
```
Neither is native aarch64; if both are unusable, the fallback is building on the
Pi itself after a minimal first install, which is slow but native.

---

## Out of scope — phase 2

Not in this plan: the `192.168.4.1` takeover, PPPoE on `eth1`, nftables/NAT,
DHCP server, DNS pointing at AdGuard Home, service migration off Debian, and
SQM/CAKE. See the phase 2 preview in the spec, including the measured
constraint that nftables flowtable offload cannot accelerate `ppp0`, capping
this Pi around 400-550 Mbps against a 450 Mbps line.
