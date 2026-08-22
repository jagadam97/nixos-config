# pella — NixOS on Raspberry Pi 4 (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a new `aarch64-linux` NixOS host `pella` on the Raspberry Pi 4, replacing Raspberry Pi OS, with static networking and no DHCP client, managed from this repo.

**Architecture:** Build a complete bootable `.raw` disk image offline with `disko`'s image builder — btrfs root, separate ext4 `/boot`, FAT32 firmware partition, all populated inside a build VM — then write it to the microSD from the macbook's built-in card reader. No installer media, no on-device partitioning, and the image can be inspected before any hardware is touched.

**Tech Stack:** nixpkgs unstable, flakes, `nixos-hardware` (new input), `disko` image builder with binfmt cross-build, btrfs, u-boot + extlinux, Tailscale.

**Spec:** `docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md`

---

## Why this shape

Three problems had to be solved together, and the offline image solves all of them:

1. **The Pi cannot install to the card it is running Debian from.** An offline
   image sidesteps this — nothing is installed on the Pi at all.
2. **btrfs rules out `sdImage`**, which only produces ext4. `disko`'s image
   builder has no such limit.
3. **`nixos-hardware` does not populate `/boot/firmware`.** `disko`'s image
   builder runs a real `nixos-install`, which runs activation scripts, so
   `hosts/pella/firmware.nix` populates it inside the VM.

Verified in `disko/lib/make-disk-image.nix`:

```
nixos-install --root "$rootMountPoint" --system <toplevel> --keep-going ...
```

`nixos-install` runs `switch-to-configuration boot`, so activation scripts and
the bootloader installer both run during the image build.

Cross-building `aarch64-linux` on x86_64 uses `disko.imageBuilder.enableBinfmt`,
which runs the build VM with an **x86_64 kernel** and binfmt for the aarch64
userland — not a fully emulated ARM VM.

## Note on verification style

This repo has no unit test suite; it is a Nix flake. The TDD analogue used
throughout is: **run the evaluation or build command, confirm it fails for the
expected reason, make the change, confirm it now succeeds.** Every task gives the
exact command and the expected output on both sides.

The single most valuable property of this plan: **Task 8 inspects the built
image before Task 9 writes anything.** A wrong firmware partition is caught as a
failed `ls`, not as a black screen.

## File structure

| File | Responsibility |
|---|---|
| `flake.nix` | Modify: add `nixos-hardware` input; add the `pella` output |
| `hosts/pella/disko.nix` | Create: three-partition layout, btrfs subvolumes, image size/name |
| `hosts/pella/firmware.nix` | Create: populate `/boot/firmware` with RPi firmware + u-boot + config.txt |
| `hosts/pella/hardware.nix` | Create: platform, initrd modules, zram, image-builder cross settings |
| `hosts/pella/default.nix` | Create: hostname, user, static networking, timezone, sops stub |

`firmware.nix` is its own file because it is the least certain part of the design
and the most likely to need iteration.

---

### Task 1: Add the `nixos-hardware` flake input

**Files:**
- Modify: `flake.nix` (`inputs` block, and the `outputs` argument list)

- [ ] **Step 1: Confirm the input is currently absent**

Run:
```bash
grep -c nixos-hardware flake.nix || echo "absent"
```
Expected: `0` or `absent`.

- [ ] **Step 2: Add the input**

In `flake.nix`, inside `inputs`, after the `disko` block:

```nix
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
```

- [ ] **Step 3: Add it to the outputs argument list**

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

- [ ] **Step 4: Verify the lock updates and the flake evaluates**

Run:
```bash
nix flake lock
nix flake metadata --json | python3 -c "import json,sys; print('nixos-hardware' in json.load(sys.stdin)['locks']['nodes'])"
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

`imageSize` is set to 12G rather than the card's full 29.8G on purpose: the image
has to be built, stored, transferred to the macbook and written over a card
reader, and every one of those is linear in image size. btrfs is grown to fill
the card in Task 10. disko has no auto-resize, so this is a deliberate choice,
not an oversight.

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

        # Image build settings. disko has no auto-resize, so this size is what
        # you get until Task 10 grows btrfs to fill the real card. Keep it well
        # under the card's 29.8G: build, transfer and dd time all scale with it.
        imageName = "pella-aarch64-rpi4";
        imageSize = "12G";

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
since the card reports discard support.

imageSize is 12G rather than the card's 29.8G because build, transfer and
dd time all scale with it; btrfs gets grown to fill the card after first
boot since disko has no auto-resize."
```

---

### Task 3: Populate the Raspberry Pi firmware partition

`nixos-hardware`'s `raspberry-pi-4` module sets the extlinux boot path but
explicitly does **not** manage the firmware partition or `config.txt`. The file
list and `config.txt` below are taken from nixpkgs'
`nixos/modules/installer/sd-card/sd-image-aarch64.nix`, reduced to the Pi 4 files.

This runs as an activation script, so it executes during the image build (via
`nixos-install`) *and* on every later `nixos-rebuild` — meaning firmware and
u-boot track nixpkgs rather than being frozen at install time.

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
# sdImage.populateFirmwareCommands, which we never run - so we do it here as an
# activation script instead. disko's image builder runs a real nixos-install,
# which runs activation, so this executes during the image build too.
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
  # a Pi 4B Rev 1.5 and the rest would just be noise on a 512M partition.
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

  # Only the activation script needs rsync, but having it on PATH makes
  # debugging the firmware partition by hand much easier.
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
the firmware partition. Without this the SoC has nothing to load and the Pi
boots to a black screen.

File list and config.txt are lifted from nixpkgs' sd-image-aarch64.nix,
reduced to the Pi 4 files. As an activation script it runs both inside
disko's image-build VM and on every later rebuild, so firmware and u-boot
track nixpkgs instead of being frozen at install time."
```

---

### Task 4: Create the hardware configuration

This file also carries the image-builder cross-compile settings, because they are
a property of how this host's image gets built on x86_64 hardware.

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
  inputs,
  ...
}:

{
  nixpkgs.hostPlatform = "aarch64-linux";

  # Build the disk image on x86_64 using binfmt for the aarch64 userland. The
  # build VM runs an x86_64 kernel, so this is not a fully emulated ARM VM -
  # only userland instructions go through qemu. Both remote builders (alienX,
  # nauvoo) are x86_64 with qemu-aarch64 registered.
  disko.imageBuilder = {
    enableBinfmt = true;
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    kernelPackages = inputs.nixpkgs.legacyPackages.x86_64-linux.linuxPackages_latest;
  };

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

Note `nixpkgs.hostPlatform` is a plain assignment, not `lib.mkDefault`. The disko
image-builder docs set it directly, and `mkDefault` risks the cross-build
settings and the platform disagreeing.

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
4GB board.

Also carries disko.imageBuilder cross settings: the image is built on
x86_64 with an x86_64 kernel plus binfmt for the aarch64 userland, so only
userland instructions go through qemu."
```

---

### Task 5: Create the host configuration

Two things to know before writing this file:

1. `modules/common/ssh.nix` computes `PasswordAuthentication = !isKayda`, a
   hostname comparison. Every host that is not `kayda` gets password auth
   **enabled**. Unacceptable for a box destined to be an internet-facing
   gateway, so this host forces it off. The shared module is left alone so no
   other host's behaviour changes.
2. `modules/common/nix-settings.nix:10` sets
   `extra-platforms = [ "i686-linux" "aarch64-linux" ]`. Meaningful on the
   x86_64 hosts, false on this one.

**Files:**
- Create: `hosts/pella/default.nix`
- Create: `hosts/pella/secrets.yaml`

- [ ] **Step 1: Create `hosts/pella/default.nix`**

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
  # host key, which does not exist until first boot, so .sops.yaml and a real
  # secrets.yaml come after the box is up - before phase 2, which needs PPPoE
  # credentials stored.
  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
}
```

- [ ] **Step 2: Create the placeholder secrets file**

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
- modules/common/nix-settings.nix advertises i686-linux, false on aarch64.

eth1 (the UE300) is left unconfigured - it becomes the PPPoE WAN in phase 2."
```

---

### Task 6: Wire up the `pella` flake output

**Files:**
- Modify: `flake.nix` (`nixosConfigurations`, after the `kayda` entry)

- [ ] **Step 1: Confirm the output does not exist yet**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.networking.hostName 2>&1 | tail -1
```
Expected: an error saying attribute `pella` is missing.

- [ ] **Step 2: Add the output**

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

There is deliberately **no** home-manager: it roughly doubles the build for no
phase-1 benefit and can be added later.

- [ ] **Step 3: Verify the output evaluates**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.networking.hostName
```
Expected: `"pella"`

- [ ] **Step 4: Verify platform and overrides resolved**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.nixpkgs.hostPlatform.system
nix eval .#nixosConfigurations.pella.config.nix.settings.extra-platforms
nix eval .#nixosConfigurations.pella.config.services.openssh.settings.PasswordAuthentication
nix eval .#nixosConfigurations.pella.config.boot.loader.generic-extlinux-compatible.enable
```
Expected, in order: `"aarch64-linux"` · `[ ]` · `false` · `true`

The last confirms `nixos-hardware`'s `raspberry-pi-4` module is applying.

- [ ] **Step 5: Verify the three filesystems and btrfs options**

Run:
```bash
nix eval --json .#nixosConfigurations.pella.config.fileSystems --apply 'fs: builtins.attrNames fs'
nix eval --json .#nixosConfigurations.pella.config.fileSystems."/".options
nix eval --json .#nixosConfigurations.pella.config.fileSystems."/boot".fsType
nix eval --json .#nixosConfigurations.pella.config.fileSystems."/boot/firmware".fsType
```
Expected: a list containing `"/"`, `"/boot"`, `"/boot/firmware"`, `"/home"`,
`"/nix"`, `"/var/lib"`, `"/var/log"`; then options containing
`"compress=zstd:3"`, `"noatime"`, `"discard=async"` and **not** `"ssd"`; then
`"ext4"`; then `"vfat"`.

- [ ] **Step 6: Verify the image derivation instantiates**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.system.build.diskoImages.drvPath
```
Expected: a `/nix/store/...drv` path.

If this errors with an unknown attribute, `disko.nixosModules.disko` is not
imported or the disko input is too old to have the image builder.

- [ ] **Step 7: Commit**

```bash
git add flake.nix
git commit -m "feat(pella): wire the pella nixosConfiguration

aarch64-linux with nixos-hardware's raspberry-pi-4 module. No home-manager:
it roughly doubles the build for no phase-1 value."
```

---

### Task 7: Build the disk image

**Files:** none — build and verification.

- [ ] **Step 1: Confirm alienX is reachable and has aarch64 binfmt**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net 'uname -m; nproc; ls /proc/sys/fs/binfmt_misc/ | grep qemu-aarch64'
```
Expected: `x86_64`, `32`, `qemu-aarch64`.

- [ ] **Step 2: Build the system closure first**

Building the closure separately means a config error surfaces before the longer
image build, and gives a cleaner error if something is wrong.

Run:
```bash
nix build .#nixosConfigurations.pella.config.system.build.toplevel --print-out-paths -L
```
Expected: a `/nix/store/...-nixos-system-pella-...` path.

- [ ] **Step 3: Verify the firmware derivation contains a bootable payload**

Run:
```bash
FW=$(nix eval --raw .#nixosConfigurations.pella.config.system.activationScripts.pellaRpiFirmware.text \
  | grep -oE '/nix/store/[a-z0-9]{32}-pella-rpi-firmware' | head -1)
echo "firmware derivation: $FW"
nix build --no-link "$FW"
ls "$FW"
```
Expected: `armstub8-gic.bin`, `bcm2711-rpi-4-b.dtb`, `bootcode.bin`,
`config.txt`, `fixup*.dat`, `start*.elf`, `u-boot.bin`.

If `u-boot.bin` or `armstub8-gic.bin` is missing, stop and fix Task 3. Nothing
downstream can boot without them.

- [ ] **Step 4: Build the image**

Run:
```bash
nix build .#nixosConfigurations.pella.config.system.build.diskoImages --print-out-paths -L
```
Expected: a store path containing `pella-aarch64-rpi4.raw`.

This runs a VM that partitions a 12G file, makes the filesystems and runs
`nixos-install`. Budget 20-60 minutes. If it fails on memory, use the script
variant instead, which takes a memory flag:

```bash
nix build .#nixosConfigurations.pella.config.system.build.diskoImagesScript
sudo ./result --build-memory 4096
```

- [ ] **Step 5: Record the image path**

Run:
```bash
IMG=$(find "$(nix build --no-link --print-out-paths .#nixosConfigurations.pella.config.system.build.diskoImages)" -name '*.raw' | head -1)
echo "$IMG"; ls -lh "$IMG"
```
Expected: a `.raw` path, 12G apparent size.

---

### Task 8: Inspect the image before writing it

This task is the whole reason for the offline-image approach. Every failure mode
that would previously have shown up as a black screen is caught here, with the
card untouched.

**Files:** none.

- [ ] **Step 1: Confirm the partition table and layout**

Run on alienX (loop mounting needs Linux):
```bash
ssh dj@alienx.owl-coho.ts.net "sudo sfdisk -l '$IMG'"
```
Expected: GPT with three partitions in this order — ~512M FAT, ~1G Linux
filesystem, remainder Linux filesystem.

**If the order is wrong** (1G ext4 first), the `priority` values in
`hosts/pella/disko.nix` did not apply. Fix Task 2 and rebuild.

- [ ] **Step 2: Attach the image to a loop device**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net "sudo losetup --show -Pf '$IMG'"
```
Expected: a device name like `/dev/loop0`. Note it; the partitions appear as
`/dev/loop0p1`, `p2`, `p3`.

- [ ] **Step 3: Verify the firmware partition — the critical check**

Run, substituting the loop device:
```bash
ssh dj@alienx.owl-coho.ts.net '
  sudo mkdir -p /mnt/pella-fw
  sudo mount /dev/loop0p1 /mnt/pella-fw
  ls -la /mnt/pella-fw
  echo "--- config.txt ---"
  cat /mnt/pella-fw/config.txt
  sudo umount /mnt/pella-fw
'
```
Expected: `bootcode.bin`, `config.txt`, `start4.elf`, `fixup4.dat`,
`u-boot.bin`, `armstub8-gic.bin`, `bcm2711-rpi-4-b.dtb`, `.pella-firmware`; and
`config.txt` containing `kernel=u-boot.bin` and `arm_64bit=1`.

**If `u-boot.bin` is absent**, the activation script did not run during
`nixos-install`. Do not write this image. See Contingencies.

- [ ] **Step 4: Verify `/boot` has extlinux and a kernel that exists**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net '
  sudo mkdir -p /mnt/pella-boot
  sudo mount /dev/loop0p2 /mnt/pella-boot
  cat /mnt/pella-boot/extlinux/extlinux.conf
  echo "--- resolving referenced files ---"
  awk "/^[[:space:]]*(LINUX|INITRD)/ {print \$2}" /mnt/pella-boot/extlinux/extlinux.conf \
    | while read f; do ls -l "/mnt/pella-boot/$f" 2>&1; done
  sudo umount /mnt/pella-boot
'
```
Expected: an `extlinux.conf` with at least one `LABEL` block, and every `LINUX`
and `INITRD` path resolving to a real file. A "No such file" means the Pi will
drop to a u-boot prompt.

- [ ] **Step 5: Verify the btrfs root, subvolumes and compression**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net '
  sudo mkdir -p /mnt/pella-root
  sudo mount -o subvol=@root /dev/loop0p3 /mnt/pella-root
  echo "--- subvolumes ---"; sudo btrfs subvolume list /mnt/pella-root
  echo "--- os-release ---"; cat /mnt/pella-root/etc/os-release | head -3
  echo "--- hostname ---";   cat /mnt/pella-root/etc/hostname 2>/dev/null
  echo "--- fstab ---";      cat /mnt/pella-root/etc/fstab
  sudo umount /mnt/pella-root
'
```
Expected: five subvolumes (`@root @nix @home @varlib @log`), NixOS in
`os-release`, `pella` as the hostname, and an `fstab` whose btrfs entries carry
`compress=zstd:3` and `discard=async`.

- [ ] **Step 6: Detach the loop device**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net 'sudo losetup -d /dev/loop0; losetup -a'
```
Expected: the device no longer listed.

- [ ] **Step 7: Copy the image to the macbook**

Run:
```bash
scp dj@alienx.owl-coho.ts.net:"$IMG" /tmp/pella-aarch64-rpi4.raw
ls -lh /tmp/pella-aarch64-rpi4.raw
```
Expected: the file present locally. If the image is on the local machine already,
skip this.

---

### Task 9: Write the image to the microSD

> **Destructive step.** This overwrites the Pi's 29.8GB microSD and destroys the
> Debian installation, including `homelab-scrapper`, `wol-server` and
> `/etc/wol-server/config.toml`, the telegraf config, and the NFS export setup.
> The user confirmed on 2026-08-22 that no backup is required.
>
> Do not run this until Task 8 passed every check.

**Files:** none.

- [ ] **Step 1: Shut the Pi down cleanly and remove the card**

Run:
```bash
ssh pi@192.168.4.230 'sudo poweroff' || true
```
Wait for it to power down, then remove the microSD and insert it into the
macbook's built-in reader.

- [ ] **Step 2: Identify the card — carefully**

Run:
```bash
diskutil list external physical
```
Expected: one entry around 31.9 GB. Note its identifier, e.g. `/dev/disk4`.

**Verify the size before continuing.** Writing to the wrong `/dev/diskN` on a
mac will destroy an internal volume. If more than one external disk is listed,
unplug the others.

- [ ] **Step 3: Unmount it (do not eject)**

Run, substituting the identifier:
```bash
diskutil unmountDisk /dev/disk4
```
Expected: `Unmount of all volumes on disk4 was successful`.

- [ ] **Step 4: Write the image**

Run, substituting the identifier. Note `rdisk` rather than `disk` — the raw
device is dramatically faster on macOS:
```bash
sudo dd if=/tmp/pella-aarch64-rpi4.raw of=/dev/rdisk4 bs=4m status=progress
```
Expected: 12 GB written, ending with a byte count and a transfer rate.

Budget 5-20 minutes depending on the card. `status=progress` needs a recent
`dd`; if unsupported, drop it and press Ctrl-T to poll progress.

- [ ] **Step 5: Flush and eject**

Run:
```bash
sync
diskutil eject /dev/disk4
```
Expected: `Disk /dev/disk4 ejected`.

- [ ] **Step 6: Reinstall the card and power on**

Put the microSD back in the Pi and apply power. First boot has to generate SSH
host keys and start Tailscale, so allow 2-3 minutes.

---

### Task 10: Confirm the system and grow btrfs to fill the card

**Files:** none.

- [ ] **Step 1: Confirm it booted**

Run:
```bash
ssh jagadam97@192.168.4.230 'hostname; uname -m; findmnt / -o SOURCE,FSTYPE'
```
Expected: `pella`, `aarch64`, `/dev/mmcblk0p3` with `btrfs`.

If SSH does not answer after 3 minutes, see Contingencies.

- [ ] **Step 2: Run the acceptance checks**

Run:
```bash
ssh jagadam97@192.168.4.230 '
  echo "--- mounts ---";    findmnt -R / -o TARGET,SOURCE,FSTYPE,OPTIONS | grep -E "btrfs|vfat|ext4"
  echo "--- subvols ---";   sudo btrfs subvolume list /
  echo "--- addr ---";      ip -br addr show eth0
  echo "--- route ---";     ip route | head -3
  echo "--- no dhcp ---";   (pgrep -a dhcpcd || pgrep -a dhclient || echo "no dhcp client")
  echo "--- eth1 ---";      ip -br link show eth1; lsusb -t | grep r8152
  echo "--- errors ---";    journalctl -p err -b --no-pager | tail -20
'
```
Expected: three filesystems mounted as designed with `compress=zstd:3` and
`discard=async`; five subvolumes; `eth0` = `192.168.4.230/24`; default route via
`192.168.4.1`; `no dhcp client`; `eth1` present with `r8152` at **5000M**; no
errors in the journal.

- [ ] **Step 3: Confirm outbound networking**

Run:
```bash
ssh jagadam97@192.168.4.230 'ping -c2 -W3 1.1.1.1 && curl -sS -o /dev/null -w "%{http_code}\n" https://cache.nixos.org/nix-cache-info'
```
Expected: two replies and `200`.

- [ ] **Step 4: Grow the root partition to fill the card**

The image was built at 12G; the card is 29.8G. GPT also needs its backup header
moved to the real end of the device.

Run:
```bash
ssh jagadam97@192.168.4.230 '
  sudo sgdisk --move-second-header /dev/mmcblk0
  sudo parted ---pretend-input-tty /dev/mmcblk0 <<< $"resizepart 3 100%\nyes\n"
  sudo partprobe /dev/mmcblk0
  lsblk -o NAME,SIZE,FSTYPE /dev/mmcblk0
'
```
Expected: `mmcblk0p3` now reports roughly 28G.

- [ ] **Step 5: Grow the btrfs filesystem**

btrfs grows online; no reboot or unmount needed.

Run:
```bash
ssh jagadam97@192.168.4.230 '
  sudo btrfs filesystem resize max /
  df -h /
  sudo btrfs filesystem usage / | head -8
'
```
Expected: `/` now shows roughly 28G total.

- [ ] **Step 6: Confirm the box can rebuild itself**

This is the real proof it is a managed host and not a one-shot image.

Run:
```bash
rsync -az --exclude .git ./ jagadam97@192.168.4.230:/tmp/nixos-config/
ssh jagadam97@192.168.4.230 'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella'
```
Expected: `switching to configuration...` with no error.

- [ ] **Step 7: Confirm the firmware activation script is idempotent**

Run:
```bash
ssh jagadam97@192.168.4.230 'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella 2>&1 | grep -i "populating /boot/firmware" || echo "skipped as expected"'
```
Expected: `skipped as expected` — the stamp file should prevent a second copy.

- [ ] **Step 8: Bring Tailscale up**

Run:
```bash
ssh jagadam97@192.168.4.230 'sudo tailscale up --hostname pella; tailscale ip -4'
```
Expected: either already connected, or a one-time login URL, then a `100.x.y.z`
address.

---

### Task 11: Add the sops age key

The host SSH key only exists now that the box has booted. This has to happen
before phase 2, which stores PPPoE credentials.

**Files:**
- Modify: `.sops.yaml`
- Modify: `hosts/pella/secrets.yaml`

- [ ] **Step 1: Derive the age key**

Run:
```bash
ssh jagadam97@192.168.4.230 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub' | nix run nixpkgs#ssh-to-age
```
Expected: a single `age1...` string. Record it.

- [ ] **Step 2: Add the key to `.sops.yaml`**

In the `keys:` block, after the `kayda` entry, using the value from Step 1:

```yaml
  - &pella age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Add a creation rule after the `kayda` rule:

```yaml
  - path_regex: hosts/pella/secrets\.yaml$
    key_groups:
      - age:
          - *pella
          - *admin
```

And add `- *pella` to the `age:` list of the `secrets/common\.yaml$` rule so this
host can read shared secrets.

- [ ] **Step 3: Provision the private age key on the host**

Run:
```bash
ssh jagadam97@192.168.4.230 '
  sudo mkdir -p /var/lib/sops-nix
  sudo sh -c "nix run nixpkgs#ssh-to-age -- -private-key -i /etc/ssh/ssh_host_ed25519_key > /var/lib/sops-nix/keys.txt"
  sudo chmod 600 /var/lib/sops-nix/keys.txt
  sudo ls -l /var/lib/sops-nix/keys.txt
'
```
Expected: a `-rw-------` file owned by root.

- [ ] **Step 4: Verify sops round-trips for this host**

Run:
```bash
printf 'placeholder: notasecret\n' > /tmp/pella-test.yaml
sops --config .sops.yaml -e /tmp/pella-test.yaml > hosts/pella/secrets.yaml
sops --config .sops.yaml -d hosts/pella/secrets.yaml
grep -c 'age1' hosts/pella/secrets.yaml
```
Expected: the decrypt prints `placeholder: notasecret`, and the file on disk
contains `sops:` metadata with age recipients.

- [ ] **Step 5: Confirm the host can decrypt after a rebuild**

Run:
```bash
rsync -az --exclude .git ./ jagadam97@192.168.4.230:/tmp/nixos-config/
ssh jagadam97@192.168.4.230 'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella && systemctl status sops-nix --no-pager | head -5'
```
Expected: the `sops-nix` unit active/exited without failure.

- [ ] **Step 6: Commit**

```bash
git add .sops.yaml hosts/pella/secrets.yaml
git commit -m "feat(pella): add sops age key

Derived from the host SSH key, which only existed once the box had booted.
Needed before phase 2, which stores PPPoE credentials."
```

---

### Task 12: Update the spec and finish the branch

**Files:**
- Modify: `docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md`

- [ ] **Step 1: Mark the spec implemented**

Change the `**Status:**` line to:

```markdown
**Status:** Implemented 2026-08-22 — see docs/superpowers/plans/2026-08-22-pella-nixos-phase1.md
```

- [ ] **Step 2: Record what diverged**

The spec still describes the two-stage pendrive install. Replace that section
with the offline-image approach, and note why: `disko`'s image builder runs a
real `nixos-install` inside a VM, so the firmware activation script runs during
the build, and the image can be inspected before hardware is touched.

Do not leave the spec describing something that was not built.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md
git commit -m "docs(pella): mark phase 1 implemented, record the offline-image change"
```

- [ ] **Step 4: Hand off**

Use the superpowers:finishing-a-development-branch skill to choose between
merging `feat/pella-nixos-router` to `main`, opening a PR, or leaving it.

---

## Contingencies

### `/boot/firmware` is empty in the built image (Task 8 Step 3)

The activation script did not run during `nixos-install`. Do not write the image.
Use the script variant of the image build, which can inject files directly:

```bash
nix build .#nixosConfigurations.pella.config.system.build.diskoImagesScript
FW=$(nix eval --raw .#nixosConfigurations.pella.config.system.activationScripts.pellaRpiFirmware.text \
  | grep -oE '/nix/store/[a-z0-9]{32}-pella-rpi-firmware' | head -1)
sudo ./result --build-memory 4096 --post-format-files "$FW" /boot/firmware
```

`--post-format-files` copies into the finished image after formatting, which is
exactly this case. Re-run Task 8 to verify.

### The Pi does not boot from the GPT image

nixpkgs' `sdImage` uses MBR, and Debian on this Pi used MBR too
(`root=PARTUUID=88d04481-02` is MBR-style). GPT is used here because disko's
`table` type is deprecated and documented as breaking its own test framework. The
2026 bootloader should read GPT, but this was not verified on this board.

If it will not boot, switch `hosts/pella/disko.nix` to MBR and rebuild the image:

```nix
        content = {
          type = "table";
          format = "msdos";
          partitions = [
            { name = "firmware"; start = "1M";    end = "513M";  fs-type = "fat32"; bootable = true;
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

### It boots but SSH never answers

Attach HDMI and a USB keyboard — with `console=tty1` set, boot messages appear on
the display. Most likely causes: `eth0` named something else by the RPi4 kernel
(check `ip -br link`), or the static address failing to apply. The image is
rebuildable and the card rewritable, so this is recoverable, just slower.

### u-boot cannot find `extlinux.conf`

This is what the separate ext4 `/boot` exists to prevent, and Task 8 Step 4
should have caught it. If u-boot cannot read ext4 either, fall back to
`raspberry-pi-nix` pinned via `flake.lock` — it drops u-boot entirely and has the
firmware load the kernel directly from `config.txt`, accepting an archived
dependency.

### `nixos-hardware`'s RPi4 kernel conflicts with something

The module pins its own `kernelPackages`. Override in
`hosts/pella/hardware.nix` with
`boot.kernelPackages = lib.mkForce pkgs.linuxPackages_rpi4;`.

### The image build runs out of memory or disk

Use the script variant with more memory:
```bash
nix build .#nixosConfigurations.pella.config.system.build.diskoImagesScript
sudo ./result --build-memory 4096
```
alienX has 61GB RAM, so memory should not be the binding constraint. If disk is
short, lower `imageSize` in `hosts/pella/disko.nix` — btrfs is grown to fill the
card in Task 10 regardless, so a smaller image costs nothing.

---

## What changed from the first version of this plan

The original plan installed via a pendrive: build a throwaway `sdImage`
installer, `dd` it to the pendrive, flip `BOOT_ORDER` to `0xf14`, boot it, run
`disko` and `nixos-install` on live hardware, flip `BOOT_ORDER` back. Fourteen
tasks.

Replaced with an offline `disko` image because it is both simpler and safer:

- No installer configuration, no pendrive, no `BOOT_ORDER` changes, no
  partitioning on live hardware
- **The image is inspected before the card is written.** A bad firmware
  partition is a failed `ls` in Task 8, not a black screen after Debian is gone
- btrfs, zstd:3 and the three-partition layout are unchanged

Cost: the card is handled physically, and the `dd` destroys Debian with no
unplug-to-rollback. Both already accepted.

---

## Out of scope — phase 2

The `192.168.4.1` takeover, PPPoE on `eth1`, nftables/NAT, DHCP server, DNS
pointing at AdGuard Home, service migration off Debian, and SQM/CAKE. See the
phase 2 preview in the spec, including the measured constraint that nftables
flowtable offload cannot accelerate `ppp0`, capping this Pi around 400-550 Mbps
against a 450 Mbps line.
