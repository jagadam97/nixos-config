# pella — NixOS on Raspberry Pi 4 (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a new `aarch64-linux` NixOS host `pella` on the Raspberry Pi 4, replacing Raspberry Pi OS, with static networking and no DHCP client, managed from this repo.

**Architecture:** Build a bootable SD-card image with nixpkgs' `sd-image-aarch64` module, verify it by loop-mount, then write it to the microSD from the macbook's built-in card reader. `sdImage` owns the partition layout, the FAT32 firmware partition and its contents, and grows the root on first boot.

**Tech Stack:** nixpkgs unstable, flakes, `nixos-hardware`, `sd-image-aarch64`, ext4, u-boot + extlinux, Tailscale.

**Spec:** `docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md`

---

## Why this shape, and what it replaced

This is the third iteration. The two earlier designs are recorded because the
reasons they were dropped are load-bearing.

**Dropped: two-stage pendrive install.** Build a throwaway `sdImage` installer,
write it to the pendrive, flip `BOOT_ORDER` to `0xf14`, boot it, run `disko` and
`nixos-install` on live hardware, flip `BOOT_ORDER` back. All of that machinery
existed only because btrfs cannot be produced by `sdImage`.

**Dropped: offline `disko` image.** Strictly better on paper — one stage, and the
image could be verified before writing. **It does not evaluate against current
nixpkgs.** disko's `lib/make-disk-image.nix:44` passes `pkgs.aggregateModules [...]`
as vmTools' `kernel` argument, which nixpkgs PR #530764 (merged 2026-06-11) made
a hard error:

```
error: vmTools: the `kernel` argument (kernel-modules) has no `target` attribute
```

That is disko issue **#1277**, open since 2026-07-06 and unfixed. disko's master
HEAD is `ff8702b4` dated **2026-06-11** — the rev already in our lock — so no
newer disko exists to update to. The `diskoImagesScript` fallback is separately
broken by issue **#1027** (`$stdenv` unset in `vmRunCommand`).

The available workaround was pinning a deliberately stale nixpkgs for
`disko.imageBuilder.pkgs`. Rejected: that puts a stalled tool plus a frozen
nixpkgs in the install path of the machine that will carry the household
internet.

**Chosen: `sd-image-aarch64`.** Maintained, needs no workaround, and it removes
three risk areas outright rather than mitigating them:

| Risk in earlier designs | Status now |
|---|---|
| `/boot/firmware` not populated (needed a hand-written activation script) | Gone — `sdImage.populateFirmwareCommands` does it |
| GPT unverified on this board | Gone — `sdImage` uses MBR, which is what Debian booted here |
| Manual partition + filesystem resize | Gone — `sdImage.expandOnBoot` |
| u-boot unable to read btrfs subvolumes | Gone — ext4 root |

**The cost, stated plainly:** ext4 instead of btrfs. No transparent compression
on a tight 30GB card, and no checksumming against SD bit rot. Accepted by the
user on 2026-08-22 in exchange for the simplicity.

## Note on verification style

No unit test suite; this is a Nix flake. The analogue used throughout: **run the
evaluation or build, confirm it fails for the expected reason, make the change,
confirm it succeeds.** Task 5 loop-mounts the built image so that a bad boot
payload is a failed `ls` rather than a black screen.

## File structure

| File | Responsibility | State |
|---|---|---|
| `flake.nix` | `nixos-hardware` input; the `pella` output | done |
| `hosts/pella/default.nix` | sd-image import, hostname, user, static networking, sops stub | done |
| `hosts/pella/hardware.nix` | platform, initrd modules, zram, sdImage settings | done |
| `hosts/pella/secrets.yaml` | placeholder until the host exists | done |

`hosts/pella/disko.nix` and `hosts/pella/firmware.nix` were deleted with the
disko approach. Neither is needed.

---

### Task 1: Add the `nixos-hardware` flake input — DONE (`ee76b22`)

- [x] Input added, `flake.lock` updated (pinned 2026-08-19)
- [x] `nixos-hardware` present in the lock
- [x] kayda, razorback and nauvoo all still evaluate — no regression
- [x] Committed

---

### Task 2: Create the host files — DONE (`2ffdf3e`, `a9bc82b`)

- [x] `hosts/pella/hardware.nix` — `aarch64-linux`, initrd modules for microSD
      plus USB/uas, zram at 50%, `sdImage.expandOnBoot`, `sdImage.compressImage = false`
- [x] `hosts/pella/default.nix` — imports `sd-image-aarch64.nix` via `modulesPath`,
      hostname `pella`, user `jagadam97` with the four keys from kayda, static
      `192.168.4.230/24`, `networking.useDHCP = false`, firewall on with port 22,
      `Asia/Kolkata`, `stateVersion = "26.11"`, sops stub
- [x] Two deliberate overrides: `PasswordAuthentication`/`KbdInteractiveAuthentication`
      forced off (`modules/common/ssh.nix` computes them as `!isKayda`, so every
      other host has password auth on), and `extra-platforms` forced to `[ ]`
      (`modules/common/nix-settings.nix:10` advertises `i686-linux`, false on aarch64)
- [x] Both files parse
- [x] Committed

---

### Task 3: Wire the flake output — DONE (`9edefec`, `a9bc82b`)

- [x] `nixosConfigurations.pella`, `system = "aarch64-linux"`, modules
      `sops-nix` + `nixos-hardware.raspberry-pi-4` + `./hosts/pella` + `./modules/common`.
      No home-manager, no disko.
- [x] Verified: `hostName = "pella"`, `hostPlatform = "aarch64-linux"`,
      `extra-platforms = [ ]`, `PasswordAuthentication = false`,
      `generic-extlinux-compatible.enable = true`
- [x] Verified: `fileSystems` = `/` and `/boot/firmware`; `/` is `ext4` on
      `/dev/disk/by-label/NIXOS_SD`
- [x] Verified: `system.build.sdImage.drvPath` instantiates
- [x] Committed

---

### Task 4: Build the image — DONE (built on razorback)

**Files:** none.

- [ ] **Step 1: Confirm alienX is reachable and has aarch64 binfmt**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net 'uname -m; nproc; ls /proc/sys/fs/binfmt_misc/ | grep qemu-aarch64'
```
Expected: `x86_64`, `32`, `qemu-aarch64`.

- [ ] **Step 2: Build the system closure first**

Building the closure separately surfaces a config error before the longer image
build, with a cleaner message.

Run:
```bash
nix build .#nixosConfigurations.pella.config.system.build.toplevel --print-out-paths -L
```
Expected: a `/nix/store/...-nixos-system-pella-...` path.

- [ ] **Step 3: Build the image**

Run:
```bash
nix build .#nixosConfigurations.pella.config.system.build.sdImage --print-out-paths -L
```
Expected: a store path containing a `.img` file.

This is an emulated aarch64 build, but `aarch64-linux` has full
`cache.nixos.org` coverage and `builders-use-substitutes = true` is already set,
so alienX pulls prebuilt binaries and emulates only uncached derivations.
Budget 20-60 minutes on a cold cache.

If it fails on a `qemu` segfault in one derivation, retry once — emulated builds
occasionally fault non-deterministically.

- [ ] **Step 4: Record the image path and size**

Run:
```bash
IMGDIR=$(nix build --no-link --print-out-paths .#nixosConfigurations.pella.config.system.build.sdImage)
IMG=$(find "$IMGDIR" -name '*.img' | head -1)
echo "$IMG"; ls -lh "$IMG"
```
Expected: a `.img` path, a few GB.

---

### Task 5: Verify the image before writing it — DONE

Every check here is free — the card has not been touched and Debian is still
running.

**Files:** none.

- [ ] **Step 1: Confirm the partition table is MBR with two partitions**

Loop mounting needs Linux, so run on alienX:
```bash
ssh dj@alienx.owl-coho.ts.net "sudo sfdisk -l '$IMG'"
```
Expected: a `dos` label with two partitions — a small FAT (~30-256M) and a
larger Linux one. **MBR is the point**: Debian booted from an MBR table on this
Pi, so this is the known-good arrangement.

- [ ] **Step 2: Attach the image to a loop device**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net "sudo losetup --show -Pf '$IMG'"
```
Expected: a device name like `/dev/loop0`, with `p1` and `p2` appearing.

- [ ] **Step 3: Verify the firmware partition — the critical check**

Run, substituting the loop device:
```bash
ssh dj@alienx.owl-coho.ts.net '
  sudo mkdir -p /mnt/pella-fw
  sudo mount /dev/loop0p1 /mnt/pella-fw
  ls -la /mnt/pella-fw
  echo "--- config.txt ---"; cat /mnt/pella-fw/config.txt
  sudo umount /mnt/pella-fw
'
```
Expected: `bootcode.bin`, `start4.elf`, `fixup4.dat`, `u-boot.bin`,
`armstub8-gic.bin`, `bcm2711-rpi-4-b.dtb`, `config.txt`; and `config.txt`
containing `kernel=u-boot.bin` and `arm_64bit=1`.

**If `u-boot.bin` is absent, do not write the image.** The SoC would have
nothing to load.

- [ ] **Step 4: Verify the root partition has extlinux and a kernel that exists**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net '
  sudo mkdir -p /mnt/pella-root
  sudo mount /dev/loop0p2 /mnt/pella-root
  echo "--- extlinux.conf ---"; cat /mnt/pella-root/boot/extlinux/extlinux.conf
  echo "--- resolving referenced files ---"
  awk "/^[[:space:]]*(LINUX|INITRD)/ {print \$2}" /mnt/pella-root/boot/extlinux/extlinux.conf \
    | while read f; do ls -l "/mnt/pella-root/boot/$f" 2>&1; done
  echo "--- identity ---"
  cat /mnt/pella-root/etc/os-release | head -2
  cat /mnt/pella-root/etc/hostname 2>/dev/null
  sudo umount /mnt/pella-root
'
```
Expected: an `extlinux.conf` with at least one `LABEL` block, every `LINUX` and
`INITRD` path resolving to a real file, NixOS in `os-release`, and `pella` as the
hostname.

A "No such file" from the resolve loop means the Pi will drop to a u-boot prompt.

- [ ] **Step 5: Detach the loop device**

Run:
```bash
ssh dj@alienx.owl-coho.ts.net 'sudo losetup -d /dev/loop0; losetup -a'
```
Expected: the device no longer listed.

- [ ] **Step 6: Copy the image to the macbook**

Run:
```bash
scp dj@alienx.owl-coho.ts.net:"$IMG" /tmp/pella-sd.img
ls -lh /tmp/pella-sd.img
```
Skip if the image is already local.

---

### Task 6: Write the image to the microSD — SUPERSEDED (written to the USB disk instead)

> **Destructive step.** This overwrites the Pi's 29.8GB microSD and destroys the
> Debian installation, including `homelab-scrapper`, `wol-server` and
> `/etc/wol-server/config.toml`, the telegraf config, and the NFS export setup.
> The user confirmed on 2026-08-22 that no backup is required.
>
> Do not run this until Task 5 passed every check.

**Files:** none.

- [ ] **Step 1: Shut the Pi down and move the card to the macbook**

Run:
```bash
ssh pi@192.168.4.230 'sudo poweroff' || true
```
Wait for power-down, then move the microSD to the macbook's built-in reader.

- [ ] **Step 2: Identify the card — carefully**

Run:
```bash
diskutil list external physical
```
Expected: one entry around 31.9 GB. Note its identifier, e.g. `/dev/disk4`.

**Verify the size before continuing.** Writing to the wrong `/dev/diskN` on a
mac destroys an internal volume. If more than one external disk is listed,
unplug the others first.

- [ ] **Step 3: Unmount it (do not eject)**

Run, substituting the identifier:
```bash
diskutil unmountDisk /dev/disk4
```
Expected: `Unmount of all volumes on disk4 was successful`.

- [ ] **Step 4: Write the image**

Note `rdisk` rather than `disk` — the raw device is dramatically faster on macOS.

Run:
```bash
sudo dd if=/tmp/pella-sd.img of=/dev/rdisk4 bs=4m status=progress
```
Expected: the full image written, ending with a byte count and transfer rate.

Budget 5-20 minutes. If `status=progress` is unsupported, drop it and press
Ctrl-T to poll.

- [ ] **Step 5: Flush and eject**

Run:
```bash
sync
diskutil eject /dev/disk4
```
Expected: `Disk /dev/disk4 ejected`.

- [ ] **Step 6: Reinstall the card and power on**

First boot generates SSH host keys, expands the root partition and starts
Tailscale, so allow 3-5 minutes.

---

### Task 7: Confirm acceptance — DONE

**Files:** none.

- [ ] **Step 1: Confirm it booted**

Run:
```bash
ssh jagadam97@192.168.4.230 'hostname; uname -m; findmnt / -o SOURCE,FSTYPE'
```
Expected: `pella`, `aarch64`, `/dev/mmcblk0p2` with `ext4`.

If SSH does not answer after 5 minutes, see Contingencies.

- [ ] **Step 2: Confirm the root grew to fill the card**

`sdImage.expandOnBoot` should have done this without intervention.

Run:
```bash
ssh jagadam97@192.168.4.230 'df -h /; lsblk -o NAME,SIZE,FSTYPE /dev/mmcblk0'
```
Expected: `/` around 28-29G, not the image's original size.

If it did not expand, do it manually:
```bash
ssh jagadam97@192.168.4.230 '
  sudo parted ---pretend-input-tty /dev/mmcblk0 <<< $"resizepart 2 100%\nyes\n"
  sudo partprobe /dev/mmcblk0
  sudo resize2fs /dev/mmcblk0p2
  df -h /
'
```

- [ ] **Step 3: Run the acceptance checks**

Run:
```bash
ssh jagadam97@192.168.4.230 '
  echo "--- mounts ---";    findmnt -R / -o TARGET,SOURCE,FSTYPE | grep -E "ext4|vfat"
  echo "--- addr ---";      ip -br addr show eth0
  echo "--- route ---";     ip route | head -3
  echo "--- no dhcp ---";   (pgrep -a dhcpcd || pgrep -a dhclient || echo "no dhcp client")
  echo "--- eth1 ---";      ip -br link show eth1; lsusb -t | grep r8152
  echo "--- firmware ---";  ls /boot/firmware | head
  echo "--- errors ---";    journalctl -p err -b --no-pager | tail -20
'
```
Expected: `/` ext4 and `/boot/firmware` vfat mounted; `eth0` =
`192.168.4.230/24`; default route via `192.168.4.1`; `no dhcp client`; `eth1`
present with `r8152` at **5000M**; firmware files present; no errors.

- [ ] **Step 4: Confirm outbound networking**

Run:
```bash
ssh jagadam97@192.168.4.230 'ping -c2 -W3 1.1.1.1 && curl -sS -o /dev/null -w "%{http_code}\n" https://cache.nixos.org/nix-cache-info'
```
Expected: two replies and `200`.

- [ ] **Step 5: Confirm the box can rebuild itself**

The real proof it is a managed host and not a one-shot image.

Run:
```bash
rsync -az --exclude .git ./ jagadam97@192.168.4.230:/tmp/nixos-config/
ssh jagadam97@192.168.4.230 'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella'
```
Expected: `switching to configuration...` with no error.

- [ ] **Step 6: Bring Tailscale up**

Run:
```bash
ssh jagadam97@192.168.4.230 'sudo tailscale up --hostname pella; tailscale ip -4'
```
Expected: already connected, or a one-time login URL, then a `100.x.y.z` address.

---

### Task 8: Add the sops age key

The host SSH key only exists now that the box has booted. Must happen before
phase 2, which stores PPPoE credentials.

**Files:**
- Modify: `.sops.yaml`
- Modify: `hosts/pella/secrets.yaml`

- [ ] **Step 1: Derive the age key**

Run:
```bash
ssh jagadam97@192.168.4.230 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub' | nix run nixpkgs#ssh-to-age
```
Expected: a single `age1...` string. Record it.

- [ ] **Step 2: Add it to `.sops.yaml`**

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

Add `- *pella` to the `age:` list of the `secrets/common\.yaml$` rule so this
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

- [ ] **Step 4: Verify sops round-trips**

Run:
```bash
printf 'placeholder: notasecret\n' > /tmp/pella-test.yaml
sops --config .sops.yaml -e /tmp/pella-test.yaml > hosts/pella/secrets.yaml
sops --config .sops.yaml -d hosts/pella/secrets.yaml
```
Expected: the decrypt prints `placeholder: notasecret`, and the file on disk
carries `sops:` metadata with age recipients.

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

### Task 9: Update the spec and finish the branch

**Files:**
- Modify: `docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md`

- [ ] **Step 1: Mark the spec implemented**

```markdown
**Status:** Implemented 2026-08-22 — see docs/superpowers/plans/2026-08-22-pella-nixos-phase1.md
```

- [ ] **Step 2: Record that btrfs was dropped and why**

The spec must not keep describing a btrfs system that was not built. State the
disko/nixpkgs incompatibility (issues #1277 and #1027, disko master stalled at
`ff8702b4`), that pinning a stale nixpkgs was rejected, and that ext4 via
`sd-image-aarch64` was chosen instead — losing compression and checksumming,
gaining a maintained tool and three fewer risk areas.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md
git commit -m "docs(pella): mark phase 1 implemented, record the move to ext4/sdImage"
```

- [ ] **Step 4: Hand off**

Use the superpowers:finishing-a-development-branch skill to choose between
merging `feat/pella-nixos-router` to `main`, opening a PR, or leaving it.

---

## Contingencies

### The Pi does not boot at all

Task 5 should have caught the causes. If it still happens, attach HDMI and a USB
keyboard — `sd-image-aarch64` sets `console=tty0` among its kernel params, so
boot messages appear on the display. The card is rewritable, so this is
recoverable, just slow.

Note the EEPROM `BOOT_ORDER` is unset, i.e. firmware default `0xf41` — SD first.
Nothing in this plan changes it, so the Pi will try the card first as it always has.

### It boots but SSH never answers

Most likely `eth0` is named something else by the RPi4 kernel, or the static
address failed to apply. Check on the console with `ip -br link`. If the
interface has a different name, set it in `hosts/pella/default.nix` and rebuild
the image.

### `nixos-hardware`'s RPi4 kernel conflicts with `sd-image-aarch64`

Both set `boot.loader.generic-extlinux-compatible.enable`, which is consistent,
but `nixos-hardware` also pins `linuxPackages_rpi4`. If the image build fails on
a kernel/DTB mismatch, drop `nixos-hardware.nixosModules.raspberry-pi-4` from the
`pella` modules list in `flake.nix` — `sd-image-aarch64` works with the generic
aarch64 kernel, which is the more heavily tested NixOS-on-ARM path. Rebuild and
re-verify.

### The emulated build is intolerably slow

Try nauvoo instead:
```bash
nix build .#nixosConfigurations.pella.config.system.build.sdImage --builders "$NAUVOO_NIX_BUILDERS"
```
Neither builder is native aarch64. Most of the closure should come prebuilt from
`cache.nixos.org`.

### Wanting btrfs back later

Two routes, neither needed for phase 1: wait for disko issue #1277 to be fixed
and rebuild with the offline image; or convert in place with `btrfs-convert`
after the system is up, which is possible but not something to attempt on a box
that is about to become the household gateway.

---

## Out of scope — phase 2

The `192.168.4.1` takeover, PPPoE on `eth1`, nftables/NAT, DHCP server, DNS
pointing at AdGuard Home, service migration off Debian, and SQM/CAKE. See the
phase 2 preview in the spec, including the measured constraint that nftables
flowtable offload cannot accelerate `ppp0`, capping this Pi around 400-550 Mbps
against a 450 Mbps line.


---

## Outcome, 2026-08-22

Phase 1 is up. pella boots NixOS 26.11.20260818 (Zokor) and is reachable at
192.168.4.230.

### What changed from the plan

**The image went to the USB disk, not the microSD.** The plan assumed the card
would be moved to the macbook. Instead the whole install was done remotely from
the running Debian: the image was `dd`'d onto the 114.6 GB SanDisk hanging off
USB3 (`/dev/sda`, which held a stale RHEL-10 installer), and the EEPROM boot
order was set to `BOOT_ORDER=0xf14` — USB first, microSD second. Debian is
untouched on the card and is still the fallback. This is strictly better: no
physical access is needed, and a firmware-level boot failure returns to Debian
by itself.

**razorback did the building.** alienX is reached over a DERP relay at 2.8 MB/s,
so copying the 4 GB result back cost more than the build. razorback is on the
LAN with aarch64 binfmt, and it writes straight to the Pi at LAN speed — the
`dd` took about four minutes end to end.

**Verification moved onto the Pi.** razorback needs an interactive sudo
password, so the loop-mount checks ran on the Pi itself against the written
device — a stronger check than inspecting the image file. Note that a NixOS
image's `/etc` entries are absolute symlinks into `/nix/store`, so they only
resolve inside a chroot; `chroot /mnt/prt $TOPLEVEL/sw/bin/bash` with `PATH` set
is the way to read them.

### Two things that bit

**`sdImage.expandOnBoot` never ran.** `expand-root-partition.service` carries
`ConditionPathExists=/nix-path-registration`, and first-boot activation deletes
that file before the unit is reached, so it was skipped on every boot — the root
stayed at 4 GB (91% full) on a 114.6 GB disk. Grown by hand:

```bash
echo ',+' | sudo sfdisk -N 2 --no-reread --force /dev/sda
sudo partprobe /dev/sda
sudo resize2fs /dev/sda2   # online, root mounted
```

Result: 113 GB, 4% used. **Expect to do this by hand again** when the root moves
to the Samsung EVO SSD.

**The first boot guard rebooted in a loop for five hours.** `/boot/firmware` is
`nofail,noauto` and the image does not ship the mount point, so `mount` failed,
`start4.elf` was never renamed — and the script rebooted anyway. USB boot stayed
bootable, so every boot re-armed the timer: 15:41, 16:02, 16:22 … 20:26. Nothing
was damaged, but the box was unusable until the boot was confirmed.

Fixed in `38e82e8`: create the mount point, and only reboot once `start4.elf` is
provably renamed. On any failure it stays up and logs, because a box that is up
and wrong can be fixed remotely and a box in a reboot loop cannot.

Confirm a boot with:

```bash
sudo touch /var/lib/pella-boot-confirmed
```

### Acceptance results

| Check | Result |
| --- | --- |
| Identity | `pella`, NixOS 26.11.20260818 (Zokor) |
| Root | `/dev/sda2` ext4, 113 GB, 4% used |
| eth0 | `bcmgenet` on `fd580000.ethernet`, static 192.168.4.230/24, gw 192.168.4.1 |
| eth1 | `r8152` USB `2-2:1.0`, down — reserved for the phase 2 PPPoE WAN |
| Outbound | `cache.nixos.org` HTTP 200 in 0.88 s, DNS resolves |
| Self-rebuild | `nixos-rebuild switch --flake .#pella` succeeds on the Pi |
| Boot guard | armed each boot, no-ops once confirmed |

### Still open

- Tailscale is running but logged out — needs `tailscale up`.
- Task 8, the sops age key, is not done. No secrets are used in phase 1.
- The root lives on a USB flash stick. Moving it to the Samsung EVO SSD is a
  re-`dd` plus a manual grow.
