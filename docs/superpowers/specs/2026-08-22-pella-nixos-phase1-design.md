# pella — NixOS on Raspberry Pi 4, Phase 1

**Date:** 2026-08-22
**Status:** Implemented, 2026-08-22 — pella boots NixOS at 192.168.4.230. See
the outcome section of `docs/superpowers/plans/2026-08-22-pella-nixos-phase1.md`
for what changed during the install. Tailscale auth and the sops age key are
still open.

**Install medium, as built:** the image was written to the 114.6 GB USB disk from
the running Debian, not to the microSD. The EEPROM boot order is `0xf14` (USB
first, microSD second), so Debian remains on the card as an untouched fallback
and no physical access is needed. `sdImage.expandOnBoot` does not fire — its
`ConditionPathExists=/nix-path-registration` is already gone by the time the unit
is reached — so the root was grown by hand with `sfdisk`/`resize2fs`.
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
| Internal storage | `mmcblk0`, 29.8GB microSD — Samsung (`manfid 0x1b`, `oemid 0x534d`, `EB1QT`), MBR table, discard supported (4 MiB granularity) |
| Built-in NIC | `eth0`, `bcmgenet`, 1000Mb/s full, MAC `d8:3a:dd:24:76:1e` |
| USB NIC | TP-Link UE300 / RTL8153, `r8152` v1.12.13, MAC `5c:62:8b:25:de:73`, Bus 002 @ 5000M |
| Pendrive | SanDisk 3.2Gen1 `0781:55a9`, 114.6GB, Bus 002 @ 5000M — unused in the final design |
| Wifi | `wlan0` down; `iw list` reports AP mode supported |
| Thermals | 54.5°C idle, `throttled=0x0` |

## Decision record

The install method changed twice during design. Both dead ends are recorded
because the reasons are load-bearing and would otherwise be rediscovered.

### Not nixos-anywhere — no kexec

Ruled out by measurement:

```
# CONFIG_KEXEC_FILE is not set
# CONFIG_KEXEC_HANDOVER is not set
CONFIG_ARCH_SUPPORTS_KEXEC_FILE=y     <- arch supports it, build didn't enable it
```

Plain `CONFIG_KEXEC` is absent from the kernel config entirely, and no
`/sys/kernel/kexec_*` entries exist at runtime. nixos-anywhere kexecs into its
installer as a mandatory step for non-NixOS targets, so it cannot work here.

### Not a two-stage pendrive install

The first design built a throwaway `sdImage` installer, wrote it to the pendrive,
set `BOOT_ORDER=0xf14`, booted it, then ran `disko` and `nixos-install` on live
hardware. Workable, but every piece of that machinery existed solely because
btrfs cannot be produced by `sdImage`. It also offered no way to verify the
result before committing to it.

### Not an offline disko image — broken upstream

Strictly better on paper: one stage, and the image could be inspected before
being written. **It does not evaluate against current nixpkgs.**

disko's `lib/make-disk-image.nix:44` passes `pkgs.aggregateModules [...]` as
vmTools' `kernel` argument. nixpkgs PR #530764, merged 2026-06-11, made that a
hard error:

```
error: vmTools: the `kernel` argument (kernel-modules) has no `target` attribute
```

- disko issue **#1277** is this error verbatim, open since 2026-07-06, unfixed
- disko's master HEAD is `ff8702b4` dated **2026-06-11** — the rev already in our
  lock. No newer disko exists to update to; the project has not moved since
  hours before the nixpkgs change landed
- the `diskoImagesScript` fallback is separately broken by issue **#1027**
  (`$stdenv` unset in `vmRunCommand`)

The one workaround was pinning a pre-2026-06-11 nixpkgs for
`disko.imageBuilder.pkgs`. **Rejected**: it puts a stalled tool plus a frozen
nixpkgs in the install path of the machine that will carry the household
internet — the same fragility argument that ruled out `raspberry-pi-nix`.

Note this only affects disko's *image builder*. Its on-device partitioning
(`diskoScript`, `formatScript`, `mountScript`) evaluates fine, which is why the
pendrive design remained viable as a fallback.

### Chosen: `sd-image-aarch64`, ext4 root

Maintained, needs no workaround, and it removes risk areas outright rather than
mitigating them:

| Risk in the earlier designs | Status |
|---|---|
| `/boot/firmware` not populated — `nixos-hardware` does not manage it, so this needed a hand-written activation script replicating `sdImage.populateFirmwareCommands` | Gone — `sdImage` does it |
| GPT support unverified on this board | Gone — `sdImage` uses MBR, which is what Debian booted from here |
| Manual partition + filesystem resize after writing | Gone — `sdImage.expandOnBoot` |
| u-boot unable to read btrfs subvolumes, requiring a separate ext4 `/boot` | Gone — ext4 root, extlinux lives on it |
| Three-partition layout diverging from the x86 hosts | Gone — two partitions |

**The cost, stated plainly:** ext4 rather than btrfs. No transparent compression
on a 30GB card that will hold a Nix store, and no checksumming to catch SD bit
rot. The user accepted this on 2026-08-22, having asked for the simpler path once
the btrfs complexity became clear.

This is a real loss, not a wash. Revisiting it is noted under Future work.

### Storage medium

Final system on the internal 29.8GB microSD, written from the macbook's built-in
SD reader. The pendrive is not used at all.

Accepted for phase 1 with a caveat recorded: a microSD is weak for a 24/7
gateway. Constant journald writes plus repeated `nixos-rebuild` are what kill
cards, and a dead card takes the whole network down rather than one service. A
USB SSD is the correct long-term medium — and it matters more now that ext4 gives
up checksumming, so a failing card will corrupt silently rather than complain.

### Debian

Expendable. User confirmed on 2026-08-22 that no backup is required. Debian
survives until the `dd` and is destroyed there. There is no unplug-to-rollback
path; the pre-write image verification is what replaces it.

## Approach

```
alienX (x86_64, aarch64 via qemu binfmt)
  └─> nix build .#nixosConfigurations.pella.config.system.build.sdImage
        └─> *.img   (MBR: FAT32 firmware | ext4 root, label NIXOS_SD)
              ├─ loop-mount and verify  <- u-boot.bin, config.txt, extlinux paths
              └─ dd to microSD from the macbook -> boot -> root expands itself
```

The verification step is the property worth protecting: loop-mounting the image
on alienX confirms `u-boot.bin`, `config.txt` and every `LINUX`/`INITRD` path in
`extlinux.conf` before the card is written. A wrong boot payload is a failed
`ls`, not a black screen after Debian is gone.

## Install sequence

1. Build the system closure, then the image, on alienX.
2. **Verification gate** — loop-mount the `.img`, check the MBR table, the
   firmware partition contents, and that `extlinux.conf`'s referenced kernel and
   initrd exist. Nothing has touched hardware yet.
3. Copy the `.img` to the macbook.
4. Power the Pi down, move the microSD to the macbook's reader, confirm the
   device identifier and size, `dd` to `/dev/rdiskN`. **This destroys Debian.**
5. Reinstall the card, power on. `sdImage.expandOnBoot` grows the root partition.
6. Confirm `nixos-rebuild switch --flake .#pella` works on the box itself.

`BOOT_ORDER` is left at the firmware default `0xf41` (SD first). Nothing in this
design changes the EEPROM.

## Disk layout

Owned by `sd-image-aarch64`, not by this repo:

| Part | FS | Mount | Purpose |
|---|---|---|---|
| `p1` | FAT32 | `/boot/firmware` | RPi firmware blobs, u-boot, `config.txt`, DTBs |
| `p2` | ext4 | `/` | Everything, including `/boot/extlinux`. Label `NIXOS_SD` |

Root is mounted by label (`/dev/disk/by-label/NIXOS_SD`), so the image is not
tied to a particular device path — it would boot equally from a USB SSD.

## Repo changes

### `flake.nix`

- New input: `nixos-hardware` (pinned 2026-08-19)
- `nixosConfigurations.pella` with `system = "aarch64-linux"`, modules
  `sops-nix` + `nixos-hardware.raspberry-pi-4` + `./hosts/pella` + `./modules/common`

**No home-manager** — it roughly doubles the build for no phase-1 value. **No
disko** — nothing partitions the disk any more.

### `hosts/pella/default.nix`

Imports `sd-image-aarch64.nix` via `modulesPath`. Hostname, user `jagadam97` with
the same four SSH keys as `hosts/kayda/default.nix`, static networking,
`Asia/Kolkata`, `system.stateVersion = "26.11"`, sops stub.

### `hosts/pella/hardware.nix`

`aarch64-linux` platform, `sdImage.expandOnBoot`, `sdImage.compressImage = false`
(so the image can be `dd`'d without decompressing), initrd modules for the
microSD plus USB/uas, zram at 50%.

### Conflicts found in existing modules

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
uncached derivations.

## Verification gate (before Debian is destroyed)

Performed by loop-mounting the built `.img` on alienX. Nothing has been written to
hardware, so every failure here is free.

- `sfdisk -l` shows an MBR (`dos`) table with two partitions: a small FAT and a
  larger Linux one
- Firmware partition contains `bootcode.bin`, `start4.elf`, `fixup4.dat`,
  `u-boot.bin`, `armstub8-gic.bin`, `bcm2711-rpi-4-b.dtb`, `config.txt`
- `config.txt` contains `kernel=u-boot.bin` and `arm_64bit=1`
- `/boot/extlinux/extlinux.conf` exists and every `LINUX`/`INITRD` path it names
  resolves to a real file
- `/etc/os-release` says NixOS and `/etc/hostname` says `pella`

## Acceptance (after the card is written and booted)

- Boots unattended from the internal microSD, no keyboard or monitor
- SSH reachable on `192.168.4.230` with an existing key
- Tailscale up, reachable on its tailnet address
- `eth0` static `192.168.4.230/24`, default route via `.1`, no DHCP client running
- Root filesystem expanded to fill the card (~28-29G) by `expandOnBoot`
- `/boot/firmware` mounted, firmware files present
- `eth1` present, driver `r8152`, still on Bus 002 at 5000M, ready for phase 2
- `nixos-rebuild switch --flake .#pella` succeeds on the box itself
- `journalctl -p err -b` clean of storage and network errors

## Risks

| Risk | Mitigation |
|---|---|
| Firmware partition missing `u-boot.bin` | Caught by the verification gate before the card is written |
| `extlinux.conf` referencing a kernel that isn't there | Caught by the verification gate — the paths are resolved explicitly |
| `nixos-hardware`'s `linuxPackages_rpi4` conflicting with `sd-image-aarch64` | Drop `nixos-hardware.nixosModules.raspberry-pi-4` from the `pella` modules; the generic aarch64 kernel is the more heavily tested NixOS-on-ARM path |
| Boots but SSH never answers | `sd-image-aarch64` sets `console=tty0`, so HDMI + keyboard shows boot messages. Most likely `eth0` renamed — check `ip -br link`. Card is rewritable |
| Writing to the wrong `/dev/diskN` on the macbook | Confirm ~31.9GB via `diskutil list external physical`, unplug other externals first |
| 30GB microSD weak for a 24/7 gateway, now without btrfs checksums | Accepted for phase 1; a USB SSD is the right medium and matters more now that corruption would be silent |
| Debian destroyed with no rollback | Accepted — user confirmed no backup required |

## Future work

- **btrfs**, if wanted later: either wait for disko issue #1277 to be fixed and
  rebuild with an offline image, or convert in place with `btrfs-convert`. Not
  something to attempt on a box about to become the household gateway.
- **USB SSD** as the root medium, before this box carries live traffic.
- **`modules/common/ssh.nix`** — the `!isKayda` password-auth logic should
  probably be inverted repo-wide rather than overridden per host.

## Phase 2 preview (not in scope)

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
