# pella — NixOS on Raspberry Pi 4, Phase 1

**Date:** 2026-08-22
**Status:** Design complete, pending user review
**Host:** `pella` (new), Raspberry Pi 4 Model B Rev 1.5, 4GB, `aarch64-linux`

## Goal

Replace Raspberry Pi OS (Debian 13 trixie) with NixOS on the Pi 4, managed from
this repo like every other host. Static networking, no DHCP client. Reachable
over SSH and Tailscale. Nothing router-related.

Phase 1 of two. The Pi is intended to become the household router once the ONT is
switched to bridge mode, but that is deliberately out of scope. A NixOS box that
boots and stays reachable is a prerequisite, and combining the two phases would
mean debugging a new OS and a new network topology simultaneously, on the machine
that carries the internet.

## Non-goals (phase 2)

- Taking over `192.168.4.1` from the ONT
- PPPoE WAN, ONT bridge-mode switch
- nftables firewall, NAT, DHCP server, DNS forwarding
- Migrating `homelab-scrapper`, `wol-server`, `telegraf`, NFS exports off Debian
- SQM/CAKE traffic shaping
- home-manager for this host

## Hardware baseline (verified on the running Debian install, 2026-08-22)

| Item | Value |
|---|---|
| Board | Pi 4B Rev 1.5, revision `c03115`, 4GB RAM |
| Kernel (Debian) | 6.18.34+rpt-rpi-v8, aarch64 |
| Bootloader EEPROM | 2026/05/17, up to date, `capabilities 0x7f` |
| `BOOT_ORDER` | unset — firmware default `0xf41` (SD, then USB) |
| VL805 (USB3) firmware | `000138c0`, up to date |
| Internal storage | `mmcblk0`, 29.8GB microSD — Samsung (`manfid 0x1b`, `oemid 0x534d`, `EB1QT`), discard supported (4 MiB granularity) |
| Built-in NIC | `eth0`, `bcmgenet`, 1000Mb/s full, MAC `d8:3a:dd:24:76:1e` |
| USB NIC | TP-Link UE300 / RTL8153, `r8152` v1.12.13, MAC `5c:62:8b:25:de:73`, Bus 002 @ 5000M |
| Pendrive | SanDisk 3.2Gen1 `0781:55a9`, 114.6GB, Bus 002 @ 5000M, `uas` |
| Pendrive throughput | 8.4 MB/s buffered read, 0 I/O errors, 0 UAS resets |
| Wifi | `wlan0` down; `iw list` reports AP mode supported |
| Thermals | 54.5°C idle, `throttled=0x0` |

## Decision record

### Install method: not nixos-anywhere

Ruled out by measurement. The Raspberry Pi kernel has no kexec:

```
# CONFIG_KEXEC_FILE is not set
# CONFIG_KEXEC_HANDOVER is not set
CONFIG_ARCH_SUPPORTS_KEXEC_FILE=y     <- arch supports it, build didn't enable it
```

Plain `CONFIG_KEXEC` is absent from the kernel config entirely, and no
`/sys/kernel/kexec_*` entries exist at runtime. nixos-anywhere kexecs into its
installer as a mandatory step for non-NixOS targets, so it cannot work here.

### Boot method: D3 — nixos-hardware + separate ext4 `/boot`

btrfs root (user requirement) is incompatible with the naive Raspberry Pi boot
path. `nixos-hardware`'s `raspberry-pi/4` module sets
`boot.loader.generic-extlinux-compatible.enable = true` and explicitly does not
manage the firmware partition or `config.txt`. That is the u-boot path: RPi
firmware loads u-boot from the FAT partition, u-boot reads
`/boot/extlinux/extlinux.conf`, then boots the kernel.

U-Boot's btrfs support is read-only and unreliable with subvolumes. With `/` on an
`@root` subvolume, u-boot would have to parse btrfs to find the kernel — the
failure mode is an unbootable Pi, not a degraded one.

Giving `/boot` its own small ext4 partition removes the problem entirely: u-boot
reads ext4, and btrfs is only ever mounted by the initrd.

Alternatives rejected:

| Option | Why not |
|---|---|
| `raspberry-pi-nix` (no u-boot, firmware loads kernel from `config.txt`) | **Archived March 2025** — both `tstat/` and the `nix-community/` fork are read-only. The technical property is correct and it would work pinned by `flake.lock`, but an unmaintained flake in the boot path of a gateway is a liability. |
| RPi4 UEFI (`pftf/RPi4`) + ESP + systemd-boot | Would exactly match the x86 hosts, and it is file-based on the FAT partition with no EEPROM/bricking risk. But it **enforces a 3GB RAM limit by default** on 4GB boards due to DMA bugs, defaults to ACPI over device tree, and documents missing drivers. Losing 25% of RAM and taking the ACPI path on a box that needs `genet` and VL805 USB rock-solid is a bad trade. |
| `sdImage` dd'd straight to the card | Produces ext4 root; no btrfs option. |
| `disko` + `nixos-install` without a separate `/boot` | Hits the u-boot/btrfs problem above. |

### Storage medium

Final system on the internal 29.8GB microSD, written from the macbook's built-in
SD reader. The pendrive is not used at all under the offline-image approach and
stays free — user preference was against a dongle permanently attached to the Pi.

Accepted for phase 1 with a caveat recorded: a microSD is weak for a 24/7
gateway. Constant journald writes plus repeated `nixos-rebuild` are what kill
cards, and a dead card takes the whole network down rather than one service. A
USB SSD is the correct long-term medium. Revisit before phase 2 goes live.

### Debian

Expendable. User confirmed on 2026-08-22 that no backup is required. Debian
survives until the `dd` in step 5 and is destroyed there. There is no
unplug-to-rollback path, which is the accepted cost of the offline-image
approach; the verification gate in step 3 is what replaces it.

## Approach: offline disk image

Build a complete bootable `.raw` image with `disko`'s image builder, inspect it,
then write it to the microSD from the macbook's built-in SD reader.

```
alienX (x86_64 + binfmt for the aarch64 userland)
  └─> nix build .#pella...system.build.diskoImages
        └─> pella-aarch64-rpi4.raw   (GPT: FAT32 firmware | ext4 /boot | btrfs root)
              ├─ loop-mount and verify  <- firmware, extlinux, subvolumes
              └─ dd to microSD from the macbook -> boot -> grow btrfs to fill card
```

### Why this rather than an installer

Three problems had to be solved together and this solves all of them:

1. **The Pi cannot install to the card it is running Debian from.** An offline
   image sidesteps it — nothing is installed on the Pi at all.
2. **btrfs rules out `sdImage`**, which only produces ext4. disko's image builder
   has no such restriction.
3. **`nixos-hardware` does not populate `/boot/firmware`.** disko's image builder
   runs a real `nixos-install`, which runs activation scripts, so
   `hosts/pella/firmware.nix` populates it inside the build VM.

Verified in `disko/lib/make-disk-image.nix`:

```
nixos-install --root "$rootMountPoint" --system <toplevel> --keep-going ...
```

`nixos-install` runs `switch-to-configuration boot`, so activation scripts and
the bootloader installer both run during the image build.

Cross-building uses `disko.imageBuilder.enableBinfmt`, which runs the build VM
with an **x86_64 kernel** and binfmt for the aarch64 userland — not a fully
emulated ARM VM.

### The property that matters most

**The image is inspected before any hardware is touched.** Loop-mounting the
`.raw` on alienX confirms `u-boot.bin`, `config.txt`, `extlinux.conf` and the
five btrfs subvolumes are all present and correct. Under the earlier
pendrive-based plan, a wrong firmware partition would have surfaced as a black
screen *after* Debian was already destroyed. Here it is a failed `ls`.

### Rejected: two-stage pendrive install

The first version of this design built a throwaway `sdImage` installer, wrote it
to the pendrive, flipped `BOOT_ORDER` to `0xf14`, booted it, and ran `disko` plus
`nixos-install` on live hardware. It worked on paper but cost an extra flake
output, two EEPROM changes, partitioning on the live box, and gave no way to
verify the result in advance. The offline image is strictly less machinery.

Its one advantage — Debian surviving as an unplug-to-rollback path during
validation — is worth nothing here, since Debian is expendable.

## Install sequence

1. Build the system closure on alienX, and verify the `pella-rpi-firmware`
   derivation actually contains `u-boot.bin` and `armstub8-gic.bin`.
2. Build the image:
   `nix build .#nixosConfigurations.pella.config.system.build.diskoImages`
3. **Verification gate** — loop-mount the `.raw` on alienX and check the
   partition order, firmware partition contents, `extlinux.conf` (including that
   its `LINUX`/`INITRD` paths resolve), and the btrfs subvolumes. Nothing has
   been written to hardware at this point.
4. Copy the `.raw` to the macbook.
5. Power the Pi down, move the microSD to the macbook's reader, confirm the
   device identifier and size, `dd` to `/dev/rdiskN`. **This destroys Debian.**
6. Reinstall the card, power on.
7. Grow partition 3 and `btrfs filesystem resize max /` to fill the card — the
   image is built at 12G and disko has no auto-resize.
8. Confirm `nixos-rebuild switch --flake .#pella` works on the box itself.

`imageSize` is 12G rather than the card's 29.8G because build, transfer and `dd`
time all scale linearly with it. Growing btrfs afterwards is online and takes
seconds.

## Disk layout (`hosts/pella/disko.nix`)

| Part | Size | FS | Mount | Purpose |
|---|---|---|---|---|
| `p1` | 512M | FAT32 | `/boot/firmware` | RPi firmware blobs + u-boot |
| `p2` | 1G | ext4 | `/boot` | extlinux config + kernels — u-boot reads this |
| `p3` | rest | btrfs | `/` | subvolumes below |

Subvolumes match the other hosts exactly — `@root`, `@nix`, `@home`, `@varlib`,
`@log` — with `compress=zstd:3 noatime discard=async`.

Three deliberate deviations from `hosts/{kayda,razorback,nauvoo}/disko.nix`:

- **`zstd:3` instead of `zstd:6`.** Level 6 is CPU-hungry, and four Cortex-A72
  cores will be competing with PPPoE softirq load in phase 2. Level 3 (the btrfs
  default) gets most of the ratio for a fraction of the CPU. The x86 hosts keep `:6`.
- **Three partitions instead of two**, for the u-boot reason above.
- **`ssd` dropped, `discard=async` added.** `ssd` is an allocation hint for real
  SSDs and does nothing on a microSD. `discard=async` replaces it with something
  that does: the card reports `discard_granularity=4194304` and
  `discard_max_bytes=170519429120`, and `fstrim` is accepted. The async variant
  keeps trims off the write path — synchronous discard can stall writes on SD.
  Granularity is a coarse 4 MiB, so only 4 MiB-aligned free regions are trimmed.

## Repo changes

### `flake.nix`

- New input: `nixos-hardware` (currently absent).
- `nixosConfigurations.pella` with `system = "aarch64-linux"`. The existing
  `linuxSystem = "x86_64-linux"` binding stays and is simply unused here.
- No separate installer output is needed: the offline image approach requires
  only the one `pella` configuration.

Modules for `pella`: `sops-nix` (wired, unused in phase 1), `disko`,
`nixos-hardware`'s `raspberry-pi/4`, `./hosts/pella`, `./modules/common`.

**No home-manager** — it roughly doubles an emulated aarch64 build for no phase-1
value. Easy to add later.

### `hosts/pella/default.nix`

- `networking.hostName = "pella"`
- User account with the same four SSH public keys as `hosts/kayda/default.nix`
- `time.timeZone = "Asia/Kolkata"`, `system.stateVersion = "26.11"` (matches kayda)
- Static networking (below)
- `nix.settings.extra-platforms = lib.mkForce [ ]`
- zram swap — Debian currently runs 2GB of zram, worth keeping on a 4GB box that
  will run `nixos-rebuild`

### `hosts/pella/hardware.nix`

Raspberry Pi 4 specifics, filesystem wiring for the three partitions.

### `hosts/pella/disko.nix`

Layout above.

### Conflict found in existing modules

`modules/common/ssh.nix` computes `PasswordAuthentication = !isKayda`, where
`isKayda` is a hostname comparison against `"kayda"`. Every host that is not
kayda therefore gets **password authentication enabled**. That is wrong for a box
destined to be an internet-facing gateway, so `pella` forces it off along with
`KbdInteractiveAuthentication`. The shared module is left untouched so no other
host's behaviour changes; worth revisiting separately as it affects nauvoo and
razorback too.

`modules/common/nix-settings.nix:10` sets
`extra-platforms = [ "i686-linux" "aarch64-linux" ]`. Correct on the x86_64 hosts,
where it enables emulated aarch64 builds via binfmt. On an aarch64 host it
advertises an `i686-linux` capability the Pi does not have, which surfaces later
as confusing build failures. Overridden per-host with `mkForce` rather than
changed globally, since the x86_64 hosts depend on it.

## Networking (phase 1)

| Interface | Config |
|---|---|
| `eth0` (built-in) | static `192.168.4.230/24` |
| Gateway | `192.168.4.1` — still the ONT in phase 1 |
| DHCP client | **none**, per requirement |
| `eth1` (UE300) | present, unconfigured. Reserved for phase 2 WAN |
| `tailscale0` | enabled, second access path from first boot |

`192.168.4.230` is the address Debian currently holds, so nothing else on the LAN
changes. Known occupants: `.1` ONT, `.200` kayda, `.240` Proxmox storage.

### Hazards this replacement clears

Debian carries a stale half-router config in `/etc/dnsmasq.conf`:
`interface=eth1`, `dhcp-range=192.168.10.50-100`, `dhcp-option=6,8.8.8.8`. It went
live when the UE300 appeared as `eth1` and served no leases only because dhcpcd
had given `eth1` a `192.168.4.9/24` address that did not match the
`192.168.10.0/24` scope. Verified: empty leases file, clean dnsmasq log.

A rogue DHCP server handing out `8.8.8.8` would bypass the AdGuard Home setup in
`modules/services/encrypted-dns.nix`. Phase 2 must not reintroduce this.

Docker on Debian also owns the nft `filter` table (`DOCKER`, `DOCKER-FORWARD`
chains) with zero containers and `docker0` down. Also cleared by replacement.

## Secrets

Deferred. sops age keys in `.sops.yaml` derive from each host's SSH host key,
which does not exist until first boot. Nothing in phase 1 needs a secret.

After first boot: `ssh-to-age` on the new host key, add a `pella` alias to
`.sops.yaml`, create `hosts/pella/secrets.yaml`. Must be done before phase 2,
which needs PPPoE credentials stored.

## Build infrastructure

No native `aarch64-linux` builder exists. Both remote builders are x86_64 with
`qemu-aarch64` binfmt:

- **alienX** — `alienx.owl-coho.ts.net`, x86_64, 32 cores, 61GB RAM, in
  `/etc/nix/machines`, declares `x86_64-linux,aarch64-linux`, maxJobs 32
- **nauvoo** — available via the `$NAUVOO_NIX_BUILDERS` override
- **macbook** — `aarch64-darwin`, cannot build `aarch64-linux` (wrong kernel, no
  `linux-builder` VM configured)

Emulation costs less than it sounds: `aarch64-linux` is a first-class nixpkgs
platform with full `cache.nixos.org` coverage, and `builders-use-substitutes = true`
is already set, so alienX pulls prebuilt aarch64 binaries and emulates only
uncached derivations — essentially image assembly and this config.

## Verification gate (step 3, on the built image, before Debian is destroyed)

Performed by loop-mounting the `.raw` on alienX. Nothing has been written to
hardware yet, so every failure here is free.

- `sfdisk -l` shows GPT with three partitions **in order**: ~512M FAT, ~1G Linux,
  remainder Linux. Wrong order means the `priority` values did not apply.
- Firmware partition contains `bootcode.bin`, `start4.elf`, `fixup4.dat`,
  `u-boot.bin`, `armstub8-gic.bin`, `bcm2711-rpi-4-b.dtb`, `config.txt`
- `config.txt` contains `kernel=u-boot.bin` and `arm_64bit=1`
- `/boot/extlinux/extlinux.conf` exists and every `LINUX`/`INITRD` path it names
  resolves to a real file
- btrfs root lists all five subvolumes; `/etc/fstab` carries `compress=zstd:3`
  and `discard=async`
- `/etc/hostname` is `pella`

## Acceptance (after the card is written and booted)

- Boots unattended from the internal microSD, no keyboard or monitor
- SSH reachable on `192.168.4.230` with an existing key
- Tailscale up, reachable on its tailnet address
- `eth0` static `192.168.4.230/24`, default route via `.1`, no DHCP client running
- All three partitions mounted; `btrfs subvolume list /` reports the five subvolumes
- `mount | grep btrfs` confirms `compress=zstd:3` and `discard=async`
- Root grown to fill the card (~28G) after `btrfs filesystem resize max /`
- `eth1` present, driver `r8152`, still on Bus 002 at 5000M, ready for phase 2
- `nixos-rebuild switch --flake .#pella` succeeds on the box itself
- A second rebuild does **not** re-copy the firmware — the stamp file makes the
  activation script idempotent
- `journalctl -p err -b` clean of storage and network errors

## Risks

| Risk | Mitigation |
|---|---|
| `/boot/firmware` comes out empty in the image | Caught by the verification gate before the card is written. Fall back to `diskoImagesScript --post-format-files` to inject the firmware directly |
| RPi bootloader can't read the GPT image | Not verified on this board; nixpkgs `sdImage` and Debian both used MBR here. Fall back to disko's `table` type with `format = "msdos"`, accepting its deprecation warning |
| u-boot can't read the ext4 `/boot` | Standard, well-trodden path — the whole point of D3. Caught by the verification gate |
| `nixos-hardware` RPi4 quirk | Fall back to `raspberry-pi-nix` pinned via `flake.lock`, accepting the unmaintained dependency |
| Boots but SSH never answers | Attach HDMI + keyboard; `console=tty1` is set so boot messages are visible. Card is rewritable |
| Writing to the wrong `/dev/diskN` on the macbook | Confirm size (~31.9GB) via `diskutil list external physical` and unplug other external disks first |
| 30GB microSD weak for a 24/7 gateway | Accepted for phase 1; revisit before phase 2 with a USB SSD |
| Debian destroyed with no rollback | Accepted — user confirmed no backup required on 2026-08-22 |

## Phase 2 preview (not in scope)

Recorded so phase 1 does not paint us into a corner:

- `eth0` becomes LAN at `192.168.4.1`; `eth1` (UE300) becomes PPPoE WAN.
  Recommendation is built-in NIC on LAN — `r8152` can reset under sustained load,
  and if that is the LAN leg you lose management access to your own gateway.
- Taking `.1` means **no existing host config needs editing** —
  `hosts/kayda/default.nix:40` already points at `192.168.4.1`.
- WAN is PPPoE, 450 Mbps plan. `pppd` 2.5.2 with `pppoe.so`/`rp-pppoe.so` and
  `8021q` are all present on Debian, confirming kernel support exists.
- **Throughput ceiling:** nftables flowtable offload cannot accelerate `ppp0`, so
  the Pi 4 runs PPPoE on the slow path, single-core softirq bound. Expect
  400-550 Mbps with RPS tuning. 450 Mbps is achievable but leaves no headroom for
  SQM/CAKE, which tops out near 250-350 Mbps on this hardware. Full line rate or
  good latency under load — not both.
- Find the ONT's bridge-mode management address (Boa httpd, currently at `.1`)
  **before** cutover, or a failed PPPoE bring-up leaves no way to diagnose.
- DHCP pool must avoid `.200`/`.230`/`.240` and hand out AdGuard Home, not `8.8.8.8`.
