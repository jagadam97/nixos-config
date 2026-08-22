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

Final system on the internal 29.8GB microSD. The pendrive is an installer only and
is freed afterward — user preference, chosen over running root from the pendrive.

Accepted for phase 1 with a caveat recorded: a microSD is weak for a 24/7
gateway. Constant journald writes plus repeated `nixos-rebuild` are what kill
cards, and a dead card takes the whole network down rather than one service. A
USB SSD is the correct long-term medium. Revisit before phase 2 goes live.

### Debian

Expendable. User confirmed on 2026-08-22 that no backup is required. Debian
survives the pendrive validation stage and is destroyed at the `disko` step.

## Approach

```
alienX (emulated aarch64 builds)
  ├─> pella-installer sdImage (ext4, throwaway)
  │     └─ dd to pendrive /dev/sda  -> boot, validate, Debian still intact
  └─> pella system closure
        └─ nix copy to installer -> disko + nixos-install onto /dev/mmcblk0 (btrfs)
```

Two configurations are needed because the final root is btrfs and `sdImage` can
only produce ext4. The installer is minimal and its ext4 root is irrelevant since
it is discarded.

The installer image bakes in SSH keys and the static IP so the whole install is
headless — no keyboard or monitor at any point.

The pendrive stage is a validation gate: NixOS is proven to boot, network, and
accept SSH before anything touches the card Debian lives on. Rollback during that
window is flipping `BOOT_ORDER` back and rebooting.

## Install sequence

1. Build the installer on alienX:
   `nix build .#pella-installer.config.system.build.sdImage`
2. Stream the image onto the pendrive `/dev/sda`, run from the Pi over SSH.
   Destroys the installer ISO currently on it. `mmcblk0` untouched.
3. `BOOT_ORDER=0xf14` (USB first, SD fallback) via `rpi-eeprom-config`.
4. Reboot. Pi boots the installer from the pendrive.
5. **Validation gate** — checklist below. Debian still intact; failure here means
   flipping `BOOT_ORDER` back to `0xf41` and rebooting into Debian.
6. Build the real system on alienX, `nix copy` the closure to the installer, then
   `disko` + `nixos-install --system <store-path>` onto `/dev/mmcblk0`.
   **This destroys Debian.** Copying a prebuilt closure avoids making the Pi
   build its own system, which would be slow on four cores.
7. `BOOT_ORDER` back to `0xf41` (SD first). Remove the pendrive.
8. Reboot. `pella` runs from the internal microSD.

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
- `nixosConfigurations.pella-installer` — minimal, `sd-image-aarch64.nix`, SSH
  keys, static IP, plus `disko` and `git`.

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

## Validation gate (step 5, on the pendrive, before Debian is destroyed)

- Pi boots unattended, no keyboard or monitor
- SSH reachable on `192.168.4.230` with an existing key
- Tailscale up, reachable on its tailnet address
- `eth0` static, no DHCP client running
- `eth1` present, driver `r8152`, still on Bus 002 at 5000M
- `journalctl -p err -b` clean of storage and network errors

## Acceptance (after step 8, on the card)

- Boots from internal microSD with the pendrive removed
- All three partitions mounted; `btrfs filesystem show` reports the five subvolumes
- `mount | grep btrfs` confirms `compress=zstd:3` and `discard=async`
- SSH and Tailscale reachable
- `nixos-rebuild switch --flake .#pella` succeeds on the box itself
- `eth1` still enumerates at 5000M, ready for phase 2

## Risks

| Risk | Mitigation |
|---|---|
| Installer image doesn't boot on RPi4 | Debian intact; flip `BOOT_ORDER` back to `0xf41` |
| u-boot can't read the ext4 `/boot` | Standard, well-trodden path — the whole point of D3 |
| `nixos-hardware` RPi4 quirk | Fall back to `raspberry-pi-nix` pinned via `flake.lock`, accepting the unmaintained dependency |
| Pendrive too slow to be usable | 8.4 MB/s is slow but error-free; sluggish boot is acceptable for a temporary stage |
| 30GB microSD weak for a 24/7 gateway | Accepted for phase 1; revisit before phase 2 with a USB SSD |
| Losing remote access mid-install | Tailscale from first boot; Pi is physically accessible |

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
