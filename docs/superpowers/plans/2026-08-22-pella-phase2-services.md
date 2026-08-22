# pella Phase 2 — Services Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the services Debian ran on the Pi — the qBittorrent metrics scraper, telegraf, the NFS client mounts and disk/temperature monitoring — onto pella declaratively, with credentials in sops.

**Architecture:** Two stages. Stage A lands everything that needs no secret, including packaging the scraper without running it, so the aarch64 Go build is proven before credentials are in play. Stage B derives pella's age key, populates `hosts/pella/secrets.yaml`, then enables telegraf and the scraper. The scraper is built from a flake in its own repo and wired here by a NixOS module; nothing about routing is in scope — the ASUS RT-AC88U owns the network edge.

**Tech Stack:** NixOS 26.11 (`aarch64-linux`), flakes, sops-nix, systemd, `buildGoModule`, telegraf, NFS v4.

**Spec:** `docs/superpowers/specs/2026-08-22-pella-phase2-services-design.md`

---

## Context you need before starting

pella is live at `192.168.4.230` and rebuilds itself. Verified working already:
`ssh jagadam97@192.168.4.230`, key-only, `sudo` needs the account password.

**The boot guard.** `pella-boot-guard.timer` fires 20 minutes into every boot. If
`/var/lib/pella-boot-confirmed` is missing it renames `start4.elf` off the USB
firmware partition and reboots, so the Pi's EEPROM falls through to Debian on the
microSD. The flag is currently present, so the guard no-ops. Before any deploy
that could break networking, delete the flag to arm it; after verifying the box
is reachable, recreate it. Never leave it armed once you are done.

**Deploying.** Rebuild on pella itself — it is proven and adds no moving parts:

```bash
rsync -a --delete --exclude 'result*' --exclude '.direnv' \
  ./ jagadam97@192.168.4.230:/tmp/nixos-config/
ssh -t jagadam97@192.168.4.230 \
  'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella'
```

The Pi is fine for Go and for `etc`/unit rebuilds. Only reach for razorback
(16 cores, LAN, aarch64 binfmt) if something needs a heavy build:

```bash
rsync -a --delete ./ jagadam97@razorback:/tmp/nixos-config/
ssh jagadam97@razorback 'cd /tmp/nixos-config && \
  nix build .#nixosConfigurations.pella.config.system.build.toplevel --print-out-paths'
```

**Rollback** is `sudo nixos-rebuild --rollback` on pella.

This deviates from the spec, which called for
`nixos-rebuild --target-host ... --use-remote-sudo` driven from razorback. That
form prompts for pella's sudo password on every deploy, and the
`wheelNeedsPassword` decision that would fix it is still open. Rebuilding on the
box is already proven, so the plan uses it and leaves the spec's method to adopt
once that decision lands.

**Do not print secrets.** Two files hold credentials: the scraper env file on the
Debian card and `hosts/pella/secrets.yaml`. Move them with redirection, never
`cat` them into terminal output.

---

## File structure

**Stage A**

- Modify `flake.nix` — add the `homelab-scrapper` input; add three module paths to the `pella` module list
- Create `modules/services/homelab-scrapper.nix` — options, system user, hardened unit. Disabled by default
- Modify `hosts/pella/default.nix` — NFS import comes via flake.nix; add `lm_sensors`, `services.smartd` off, correct the stale eth1 comment
- Upstream, in `jagadam97/homelab-scrapper`: create `flake.nix`

**Stage B**

- Modify `.sops.yaml` — `&pella` anchor plus a `hosts/pella/secrets.yaml` rule
- Create `hosts/pella/secrets.yaml` — sops-encrypted
- Modify `modules/services/telegraf.nix` — options for URL, org, bucket and extra inputs, defaulting to today's values
- Modify `hosts/pella/default.nix` — telegraf settings, scraper enable, drop `sops.age.keyFile`
- Modify `docs/superpowers/specs/2026-08-22-pella-phase2-services-design.md` — mark implemented

---

# Stage A — no secrets

### Task 1: NFS mounts, sensors, and a corrected eth1 comment

**Files:**
- Modify: `flake.nix` (pella module list, around line 163)
- Modify: `hosts/pella/default.nix`

- [ ] **Step 1: Confirm the mounts are absent, so the check means something**

Run:
```bash
ssh jagadam97@192.168.4.230 'ls /mnt/bx1000 /mnt/bx500 /mnt/hd4000 2>&1 | head -3'
```
Expected: `No such file or directory` for all three.

- [ ] **Step 2: Add the NFS module to pella's module list**

In `flake.nix`, in the `pella` block, after `./modules/common`:

```nix
            ./modules/common
            ./modules/services/nfs-mounts.nix
```

- [ ] **Step 3: Add sensors and the disabled smartd to the host**

In `hosts/pella/default.nix`, before `system.stateVersion`:

```nix
  environment.systemPackages = with pkgs; [ lm_sensors ];

  # Disk health monitoring is wired but off. The only attached disk is the USB
  # stick this system boots from, and SMART passthrough over a USB bridge is
  # unreliable - a unit that always fails just teaches you to ignore it. Turn
  # this on when the root moves to the Samsung EVO SSD.
  services.smartd.enable = false;
```

- [ ] **Step 4: Correct the stale eth1 comment**

In `hosts/pella/default.nix`, replace:

```nix
  # eth1 is the TP-Link UE300 (RTL8153, MAC 5c:62:8b:25:de:73). Left
  # unconfigured on purpose - it becomes the PPPoE WAN in phase 2.
```

with:

```nix
  # eth1 is the TP-Link UE300 (RTL8153, MAC 5c:62:8b:25:de:73). It was going to
  # be the PPPoE WAN, but the ASUS RT-AC88U owns the network edge now, so it
  # stays down and unconfigured. Its name is still pinned by MAC below in case
  # it is ever used.
```

- [ ] **Step 5: Verify the mounts are in the built config**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.fileSystems --apply 'builtins.attrNames'
```
Expected: `[ "/" "/boot/firmware" "/mnt/bx1000" "/mnt/bx500" "/mnt/hd4000" ]`

- [ ] **Step 6: Verify the automount property that keeps boot safe**

Run:
```bash
nix eval .#nixosConfigurations.pella.config.fileSystems."/mnt/hd4000".options
```
Expected: a list containing `x-systemd.automount` and `x-systemd.mount-timeout=10`.
If either is missing, stop — a console-less box must not block boot on a dead
NFS server.

- [ ] **Step 7: Deploy**

```bash
rsync -a --delete --exclude 'result*' --exclude '.direnv' \
  ./ jagadam97@192.168.4.230:/tmp/nixos-config/
ssh -t jagadam97@192.168.4.230 \
  'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella'
```
Expected: ends with `Done. The new configuration is /nix/store/...`

- [ ] **Step 8: Verify the automounts resolve on access**

Run:
```bash
ssh jagadam97@192.168.4.230 'for m in bx1000 bx500 hd4000; do
  echo "--- $m ---"; ls /mnt/$m >/dev/null 2>&1 && echo mounted || echo FAILED
done; findmnt -t nfs4 -no TARGET'
```
Expected: `mounted` three times, and all three paths listed by `findmnt`.

- [ ] **Step 9: Verify sensors read**

Run:
```bash
ssh jagadam97@192.168.4.230 'sensors 2>&1 | head -5; cat /sys/class/thermal/thermal_zone0/temp'
```
Expected: a temperature in millidegrees, e.g. `48000`. `sensors` may report no
chips on a Pi — the thermal zone is what telegraf will read in stage B.

- [ ] **Step 10: Commit**

```bash
git add flake.nix hosts/pella/default.nix
git commit -m "feat(pella): mount the Proxmox NFS shares and add sensors

The three /mnt/pve exports from 192.168.4.240 are what Debian mounted, and
nfs-mounts.nix already uses x-systemd.automount with a 10s timeout, so an
unreachable storage host cannot hang boot on a machine with no console.

smartd is wired but off: the only attached disk is the USB stick this system
boots from, and SMART over a USB bridge is unreliable."
```

---

### Task 2: Add a flake to the scraper's own repo

This is a commit in `jagadam97/homelab-scrapper`, not in nixos-config. The repo
is Go 1.26.4, module `github.com/jagadam97/homelab-scrapper`, with one command
at `cmd/scraper`. Note the spelling: the repo is *scrapper*, the binary is
*scraper*.

**Files:**
- Create: `flake.nix` in `jagadam97/homelab-scrapper`

- [ ] **Step 1: Clone the repo somewhere scratch**

```bash
cd /private/tmp/claude-502/-Users-dinesh-reddy-repos-nixos-config/*/scratchpad
gh repo clone jagadam97/homelab-scrapper
cd homelab-scrapper
```

- [ ] **Step 2: Write flake.nix with a placeholder vendorHash**

```nix
{
  description = "Homelab qBittorrent metrics scraper";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          default = homelab-scrapper;

          homelab-scrapper = pkgs.buildGoModule {
            pname = "homelab-scrapper";
            version = "0-unstable-2026-08-22";
            src = ./.;
            vendorHash = nixpkgs.lib.fakeHash;
            subPackages = [ "cmd/scraper" ];
            ldflags = [
              "-s"
              "-w"
            ];
            meta = {
              description = "Scrapes qBittorrent stats into InfluxDB";
              mainProgram = "scraper";
            };
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell { packages = [ pkgs.go ]; };
        }
      );
    };
}
```

- [ ] **Step 3: Build it and read the real vendorHash out of the failure**

```bash
git add flake.nix && nix build .#packages.aarch64-darwin.default 2>&1 | tail -6
```
Expected: a hash mismatch naming `got: sha256-...`. Copy that value.

If it instead fails with `go.mod requires go >= 1.26.4`, change
`pkgs.buildGoModule` to `pkgs.buildGo126Module` and rerun this step.

- [ ] **Step 4: Replace the placeholder with the real hash**

Substitute the `got:` value for `nixpkgs.lib.fakeHash`:

```nix
            vendorHash = "sha256-PASTE_THE_GOT_VALUE_HERE";
```

- [ ] **Step 5: Verify the build passes and produces the binary**

```bash
nix build .#packages.aarch64-darwin.default && ls -l result/bin/
```
Expected: `result/bin/scraper`.

- [ ] **Step 6: Verify the aarch64-linux build, which is what pella runs**

```bash
rsync -a ./ jagadam97@razorback:/tmp/homelab-scrapper/
ssh jagadam97@razorback 'cd /tmp/homelab-scrapper && \
  nix build .#packages.aarch64-linux.default --print-out-paths -L 2>&1 | tail -3'
```
Expected: a `/nix/store/...-homelab-scrapper-...` path. If the vendorHash
differs per platform, something is wrong — the hash is platform-independent.

- [ ] **Step 7: Commit and push upstream**

```bash
git add flake.nix
git commit -m "build: package with Nix

buildGoModule so the scraper can be a flake input for the NixOS host that
runs it, instead of a binary copied into /usr/local/bin by a deploy script."
git push origin main
```

- [ ] **Step 8: Record the commit sha for the next task**

```bash
git rev-parse HEAD
```

---

### Task 3: Wire the scraper as a flake input

**Files:**
- Modify: `flake.nix` (inputs block, around line 29)

- [ ] **Step 1: Add the input**

In `flake.nix`, after the `nixpkgs-jellyfin` line:

```nix
    # The scraper is packaged in its own repo; this pulls that build. Private
    # repo, so whoever evaluates needs GitHub access - the macbook and
    # razorback have it, pella does not.
    homelab-scrapper = {
      url = "git+ssh://git@github.com/jagadam97/homelab-scrapper.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 2: Lock it**

```bash
nix flake lock --update-input homelab-scrapper 2>&1 | tail -3
```
Expected: `• Added input 'homelab-scrapper':` with the sha from Task 2 Step 8.

If it fails to fetch, your ssh key is not on the repo — verify with
`ssh -T git@github.com` and `gh repo view jagadam97/homelab-scrapper`.

- [ ] **Step 3: Verify the package evaluates for pella's platform**

```bash
nix eval --raw .#inputs.homelab-scrapper.packages.aarch64-linux.default.outPath
```
Expected: a `/nix/store/...-homelab-scrapper-...` path.

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat: add the homelab-scrapper flake input

Build recipe lives with the source; this repo just consumes it."
```

---

### Task 4: The scraper module, disabled

**Files:**
- Create: `modules/services/homelab-scrapper.nix`
- Modify: `flake.nix` (pella module list)

- [ ] **Step 1: Write the module**

Create `modules/services/homelab-scrapper.nix`:

```nix
# Homelab qBittorrent metrics scraper.
#
# The package comes from the app's own flake; this module owns the NixOS side
# only - a system user, the environment file holding its credentials, and a
# hardened unit. Disabled until hosts/pella/default.nix points environmentFile
# at a sops secret.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.homelabScrapper;
in
{
  options.services.homelabScrapper = {
    enable = lib.mkEnableOption "the homelab qBittorrent metrics scraper";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.homelab-scrapper.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.homelab-scrapper.packages.\${system}.default";
      description = "Scraper package to run.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      example = "/run/secrets/homelab-scrapper.env";
      description = ''
        File holding QBIT_URL, QBIT_API_KEY, INFLUX_URL, INFLUX_TOKEN,
        INFLUX_ORG, INFLUX_BUCKET and SCRAPE_INTERVAL, one KEY=value per line.
        Must be readable by the homelab-scrapper user, so point it at a sops
        secret with that owner.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.homelab-scrapper = {
      isSystemUser = true;
      group = "homelab-scrapper";
      description = "homelab-scrapper service user";
    };
    users.groups.homelab-scrapper = { };

    systemd.services.homelab-scrapper = {
      description = "Homelab qBittorrent metrics scraper";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        EnvironmentFile = cfg.environmentFile;
        Restart = "on-failure";
        RestartSec = "5s";
        User = "homelab-scrapper";
        Group = "homelab-scrapper";

        # Outbound connections to qBittorrent and InfluxDB are all it needs.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
```

- [ ] **Step 2: Add it to pella's module list**

In `flake.nix`, in the `pella` block:

```nix
            ./modules/services/nfs-mounts.nix
            ./modules/services/homelab-scrapper.nix
```

- [ ] **Step 3: Verify it evaluates and stays off**

```bash
nix eval .#nixosConfigurations.pella.config.systemd.services --apply \
  's: builtins.hasAttr "homelab-scrapper" s'
```
Expected: `false` — the module is imported but disabled, so no unit exists yet.

- [ ] **Step 4: Verify the package resolves through the option**

```bash
nix eval --raw .#nixosConfigurations.pella.config.services.homelabScrapper.package.outPath
```
Expected: the same store path as Task 3 Step 3.

- [ ] **Step 5: Commit**

```bash
git add modules/services/homelab-scrapper.nix flake.nix
git commit -m "feat(pella): add the homelab-scrapper module, disabled

Hardening mirrors the wol-server unit Debian ran, which was already strict.
A static system user rather than DynamicUser, so the sops secret can be owned
by a known uid. Stays off until stage B provides the env file."
```

---

### Task 5: Prove a reboot is still safe

**Files:** none.

- [ ] **Step 1: Arm the guard**

```bash
ssh -t jagadam97@192.168.4.230 'sudo rm /var/lib/pella-boot-confirmed && \
  systemctl list-timers pella-boot-guard --no-pager | head -3'
```
Expected: the flag gone, the timer listed.

- [ ] **Step 2: Reboot**

```bash
ssh -t jagadam97@192.168.4.230 'sudo systemctl reboot'
```

- [ ] **Step 3: Wait for it to come back and check everything survived**

```bash
sleep 60
ssh -o StrictHostKeyChecking=accept-new jagadam97@192.168.4.230 \
  'hostname; uptime; findmnt -t nfs4 -no TARGET; df -h / | tail -1'
```
Expected: `pella`, a fresh uptime, all three NFS targets, root still 113G.

If it does not come back within 25 minutes the guard will have returned the Pi
to Debian — reach it with `ssh pi@192.168.4.230`, then read the reason with
`sudo journalctl -b -1 -u pella-boot-guard`.

- [ ] **Step 4: Confirm the boot**

```bash
ssh -t jagadam97@192.168.4.230 'sudo touch /var/lib/pella-boot-confirmed'
```
Expected: no output. Do not skip this — an unconfirmed boot reboots every 20
minutes.

---

# Stage B — secrets

### Task 6: Give pella a sops identity

**Files:**
- Modify: `.sops.yaml`
- Create: `hosts/pella/secrets.yaml`
- Modify: `hosts/pella/default.nix`

- [ ] **Step 1: Rotate the leaked InfluxDB token first**

The token telegraf used on Debian was printed into a session transcript on
2026-08-22. In the InfluxDB UI at `http://192.168.4.248:8086`, create a new
token with write access to the `pi` bucket in org `oracle` and delete the old
one. Keep the new value in your clipboard or password manager — the next steps
consume it without echoing it.

First confirm the blast radius is only pella. The other hosts write to a
different endpoint, so their tokens should be unrelated:

```bash
nix eval .#nixosConfigurations.nauvoo.config.services.telegraf.extraConfig.outputs.influxdb_v2 \
  --apply 'o: (builtins.head o).urls'
```
Expected: `[ "https://influx.jagadam97.uk/" ]` - a different server from
192.168.4.248, so deleting the LAN token cannot break nauvoo or kayda. If it
returns the LAN address, stop: the token is shared, and rotating it means
updating their secrets in the same change.

- [ ] **Step 2: Derive pella's age key**

```bash
ssh jagadam97@192.168.4.230 'cat /etc/ssh/ssh_host_ed25519_key.pub' \
  | nix run nixpkgs#ssh-to-age
```
Expected: one `age1...` line. This is a public key; it is safe to paste into
`.sops.yaml` and into git.

- [ ] **Step 3: Add the anchor and the creation rule**

In `.sops.yaml`, after the `&kayda` line:

```yaml
  - &pella age1PASTE_THE_DERIVED_KEY_HERE
```

and after the `hosts/kayda/secrets.yaml` rule:

```yaml
  - path_regex: hosts/pella/secrets\.yaml$
    key_groups:
      - age:
          - *pella
          - *admin
```

- [ ] **Step 4: Move the scraper's env file off the Debian card without printing it**

The Debian root should still be mounted read-only at `/mnt/debian` on pella; if
not, `sudo mount -o ro /dev/mmcblk0p2 /mnt/debian` first.

```bash
ssh jagadam97@192.168.4.230 \
  'sudo cat /mnt/debian/etc/homelab-scrapper.env' > /tmp/scrapper.env
wc -l /tmp/scrapper.env
```
Expected: 7 — the seven `KEY=value` lines. Do not `cat` this file.

- [ ] **Step 5: Build the secrets file**

`INFLUX_TOKEN` is consumed by telegraf as an EnvironmentFile, so its value must
be a full `KEY=value` line, matching how the other hosts store it. The scraper
gets all seven lines as one multi-line value.

```bash
read -rs -p "new INFLUX_TOKEN: " NEW_TOKEN; echo
NEW_TOKEN="$NEW_TOKEN" python3 -c '
import os
env = open("/tmp/scrapper.env").read().strip().split("\n")
tok = os.environ["NEW_TOKEN"]
env = [f"INFLUX_TOKEN={tok}" if l.startswith("INFLUX_TOKEN=") else l for l in env]
body = "\n".join("    " + l for l in env)
open("hosts/pella/secrets.yaml", "w").write(
    f"INFLUX_TOKEN: INFLUX_TOKEN={tok}\n"
    f"homelab-scrapper.env: |\n{body}\n"
)
'
unset NEW_TOKEN
sops -e -i hosts/pella/secrets.yaml
head -3 hosts/pella/secrets.yaml
shred -u /tmp/scrapper.env
```

`read -rs` keeps the token off the screen. It is unset straight after so it does
not linger in the shell environment.
Expected: `head` shows `INFLUX_TOKEN: ENC[AES256_GCM,...` — encrypted, safe to
commit. If it shows plaintext, stop and do not commit.

- [ ] **Step 6: Switch to the default sops key path**

In `hosts/pella/default.nix`, delete this line:

```nix
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
```

sops-nix then falls back to `sops.age.sshKeyPaths`, which defaults to the host
key the age key in Step 2 was derived from. Nothing to provision, nothing to
lose on a reinstall.

- [ ] **Step 7: Verify sops can decrypt for pella**

```bash
nix eval .#nixosConfigurations.pella.config.sops.age.sshKeyPaths
```
Expected: `[ "/etc/ssh/ssh_host_ed25519_key" ]`

```bash
sops -d hosts/pella/secrets.yaml | grep -c "^INFLUX_TOKEN"
```
Expected: `1`. This decrypts with your admin key, proving the file is valid
without printing the values.

- [ ] **Step 8: Commit**

```bash
git add .sops.yaml hosts/pella/secrets.yaml hosts/pella/default.nix
git commit -m "feat(pella): add the sops identity and secrets

Age key derives from the host SSH key, so sshKeyPaths finds it without a
provisioned key file - one less thing to lose on a reinstall.

The InfluxDB token in here is a fresh one; the value Debian used was exposed
in a terminal transcript and has been deleted in InfluxDB."
```

---

### Task 7: Make telegraf's endpoint per-host

`modules/services/telegraf.nix` hardcodes `https://influx.jagadam97.uk/` and the
`officeServers` bucket. nauvoo and kayda import it (flake.nix lines 63 and 131)
and must not change. pella needs the LAN InfluxDB and the `pi` bucket.

**Files:**
- Modify: `modules/services/telegraf.nix`

- [ ] **Step 1: Record the current derivations, so "unchanged" is provable**

```bash
nix eval --raw .#nixosConfigurations.nauvoo.config.system.build.toplevel.drvPath > /tmp/nauvoo-before
nix eval --raw .#nixosConfigurations.kayda.config.system.build.toplevel.drvPath > /tmp/kayda-before
cat /tmp/nauvoo-before /tmp/kayda-before
```
Expected: two `/nix/store/*.drv` paths.

- [ ] **Step 2: Add options with today's values as defaults**

At the top of `modules/services/telegraf.nix`, replace the header:

```nix
# Telegraf metrics collection
{ config, pkgs, ... }:

{
```

with:

```nix
# Telegraf metrics collection.
#
# Defaults target the hosted InfluxDB the x86_64 machines use. pella overrides
# them because it writes to the LAN InfluxDB and its own bucket.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.telegrafMetrics;
in
{
  options.services.telegrafMetrics = {
    influxUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://influx.jagadam97.uk/" ];
      description = "InfluxDB v2 write endpoints.";
    };

    organization = lib.mkOption {
      type = lib.types.str;
      default = "oracle";
      description = "InfluxDB organisation.";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "officeServers";
      description = "InfluxDB bucket to write into.";
    };

    extraInputs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.attrs);
      default = { };
      example = {
        temp = [ { } ];
      };
      description = "Host-specific telegraf inputs, merged over the shared set.";
    };
  };

```

- [ ] **Step 3: Consume the options in the output block**

Replace:

```nix
      outputs.influxdb_v2 = [{
        urls = [ "https://influx.jagadam97.uk/" ];
        token = "$INFLUX_TOKEN";
        organization = "oracle";
        bucket = "officeServers";
      }];
```

with:

```nix
      outputs.influxdb_v2 = [{
        urls = cfg.influxUrls;
        token = "$INFLUX_TOKEN";
        organization = cfg.organization;
        bucket = cfg.bucket;
      }];
```

- [ ] **Step 4: Merge the extra inputs**

Change the `inputs = {` line to `inputs = {` … and append `} // cfg.extraInputs;`
in place of the closing `};` of the `inputs` attrset. The result reads:

```nix
      inputs = {
        cpu = [{ percpu = true; totalcpu = true; report_active = true; }];
        mem = [{}];
        swap = [{}];
        system = [{}];
        kernel = [{}];
        processes = [{}];
        interrupts = [{}];
        linux_sysctl_fs = [{}];
        disk = [{ ignore_fs = [ "tmpfs" "devtmpfs" "devfs" "overlay" "squashfs" ]; }];
        diskio = [{}];
        net = [{}];
        netstat = [{}];
        nstat = [{}];
        internal = [{}];
        procstat = [
          { exe = "nix-daemon"; }
          { exe = "influxd"; }
        ];
      } // cfg.extraInputs;
```

- [ ] **Step 5: Prove nauvoo and kayda are byte-identical**

```bash
nix eval --raw .#nixosConfigurations.nauvoo.config.system.build.toplevel.drvPath > /tmp/nauvoo-after
nix eval --raw .#nixosConfigurations.kayda.config.system.build.toplevel.drvPath > /tmp/kayda-after
diff /tmp/nauvoo-before /tmp/nauvoo-after && diff /tmp/kayda-before /tmp/kayda-after && echo UNCHANGED
```
Expected: `UNCHANGED`. Any diff means a default drifted — fix it before moving
on; these are live hosts.

- [ ] **Step 6: Commit**

```bash
git add modules/services/telegraf.nix
git commit -m "refactor(telegraf): make the Influx endpoint per-host

pella writes to the LAN InfluxDB at 192.168.4.248 and its own bucket, so the
endpoint cannot stay hardcoded. Defaults keep nauvoo and kayda byte-identical -
verified by comparing toplevel drvPaths before and after."
```

---

### Task 8: Enable telegraf on pella

**Files:**
- Modify: `flake.nix` (pella module list)
- Modify: `hosts/pella/default.nix`

- [ ] **Step 1: Add the module to pella**

In `flake.nix`, in the `pella` block:

```nix
            ./modules/services/homelab-scrapper.nix
            ./modules/services/telegraf.nix
```

- [ ] **Step 2: Point it at the LAN InfluxDB**

In `hosts/pella/default.nix`, after the smartd block:

```nix
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
```

- [ ] **Step 3: Verify the rendered config before deploying**

```bash
nix eval --raw .#nixosConfigurations.pella.config.services.telegraf.extraConfig.outputs.influxdb_v2 \
  --apply 'o: (builtins.head o).bucket'
```
Expected: `pi`

```bash
nix eval .#nixosConfigurations.pella.config.sops.secrets.INFLUX_TOKEN.owner
```
Expected: `"telegraf"`

- [ ] **Step 4: Deploy**

```bash
rsync -a --delete --exclude 'result*' --exclude '.direnv' \
  ./ jagadam97@192.168.4.230:/tmp/nixos-config/
ssh -t jagadam97@192.168.4.230 \
  'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella'
```
Expected: ends with `Done. The new configuration is /nix/store/...`

- [ ] **Step 5: Verify sops decrypted on the host**

```bash
ssh -t jagadam97@192.168.4.230 \
  'systemctl is-active sops-install-secrets 2>/dev/null; sudo ls -l /run/secrets/INFLUX_TOKEN'
```
Expected: the file exists, owned by `telegraf`. `sops-install-secrets` is a
oneshot, so `inactive` after success is normal — the file is the real check.

- [ ] **Step 6: Verify metrics actually land, not just that the unit runs**

```bash
ssh jagadam97@192.168.4.230 'systemctl is-active telegraf; sleep 30
  journalctl -u telegraf -n 30 --no-pager | grep -iE "wrote|error|unauthorized" | tail -5'
```
Expected: `active`, and a `Wrote batch of N metrics` line. `unauthorized` means
the rotated token is wrong or lacks write access to the `pi` bucket.

- [ ] **Step 7: Commit**

```bash
git add flake.nix hosts/pella/default.nix
git commit -m "feat(pella): enable telegraf against the LAN InfluxDB

Same target Debian used - bucket pi on 192.168.4.248 - so existing dashboards
keep working, plus the thermal input the Pi actually has."
```

---

### Task 9: Enable the scraper

**Files:**
- Modify: `hosts/pella/default.nix`

- [ ] **Step 1: Wire the secret and turn it on**

In `hosts/pella/default.nix`, after the telegraf block:

```nix
  # The scraper reads its qBittorrent and InfluxDB credentials from one env
  # file, so the whole file is the secret rather than individual keys.
  sops.secrets."homelab-scrapper.env" = {
    owner = "homelab-scrapper";
    group = "homelab-scrapper";
  };

  services.homelabScrapper = {
    enable = true;
    environmentFile = config.sops.secrets."homelab-scrapper.env".path;
  };
```

- [ ] **Step 2: Verify the unit now exists and points at the secret**

```bash
nix eval --raw .#nixosConfigurations.pella.config.systemd.services.homelab-scrapper.serviceConfig.EnvironmentFile
```
Expected: `/run/secrets/homelab-scrapper.env`

```bash
nix eval --raw .#nixosConfigurations.pella.config.systemd.services.homelab-scrapper.serviceConfig.ExecStart
```
Expected: a store path ending `/bin/scraper`.

- [ ] **Step 3: Deploy**

```bash
rsync -a --delete --exclude 'result*' --exclude '.direnv' \
  ./ jagadam97@192.168.4.230:/tmp/nixos-config/
ssh -t jagadam97@192.168.4.230 \
  'cd /tmp/nixos-config && sudo nixos-rebuild switch --flake .#pella'
```
Expected: ends with `Done. The new configuration is /nix/store/...`

- [ ] **Step 4: Verify it runs and reaches both endpoints**

```bash
ssh jagadam97@192.168.4.230 'systemctl is-active homelab-scrapper; sleep 30
  journalctl -u homelab-scrapper -n 30 --no-pager | tail -10'
```
Expected: `active`, and log lines showing a successful qBittorrent scrape and an
InfluxDB write. A 403 from qBittorrent means `QBIT_API_KEY` did not survive the
move; a 401 from InfluxDB means the rotated token needs write access to `pi`.

- [ ] **Step 5: Verify the hardening did not break it**

```bash
ssh jagadam97@192.168.4.230 'systemctl show homelab-scrapper \
  -p ProtectSystem -p User -p MemoryDenyWriteExecute -p NoNewPrivileges'
```
Expected: `ProtectSystem=strict`, `User=homelab-scrapper`,
`MemoryDenyWriteExecute=yes`, `NoNewPrivileges=yes`. If the service crash-loops
with a permission error, the log will name the syscall or path — relax that one
setting, do not remove the whole set.

- [ ] **Step 6: Commit**

```bash
git add hosts/pella/default.nix
git commit -m "feat(pella): enable the homelab-scrapper service

Env file comes from sops owned by the service user. This is the last thing
Debian was doing that pella now does."
```

---

### Task 10: Reboot, then close the phase out

**Files:**
- Modify: `docs/superpowers/specs/2026-08-22-pella-phase2-services-design.md`

- [ ] **Step 1: Arm the guard and reboot**

```bash
ssh -t jagadam97@192.168.4.230 'sudo rm /var/lib/pella-boot-confirmed && sudo systemctl reboot'
```

- [ ] **Step 2: Verify everything comes back together**

```bash
sleep 75
ssh jagadam97@192.168.4.230 'hostname; uptime
  for u in telegraf homelab-scrapper; do echo "$u: $(systemctl is-active $u)"; done
  findmnt -t nfs4 -no TARGET
  sudo -n ls /run/secrets/ 2>/dev/null || echo "(secrets need sudo to list)"'
```
Expected: `pella`, fresh uptime, both units `active`, three NFS targets. Secrets
being regenerated on boot is the point of this step — a unit that only works
until the next reboot is not migrated.

- [ ] **Step 3: Confirm the boot**

```bash
ssh -t jagadam97@192.168.4.230 'sudo touch /var/lib/pella-boot-confirmed'
```

- [ ] **Step 4: Unmount the Debian reference copy**

Its purpose is served, and leaving the old root mounted invites confusion.

```bash
ssh -t jagadam97@192.168.4.230 'sudo umount /mnt/debian 2>/dev/null; findmnt /mnt/debian || echo unmounted'
```
Expected: `unmounted`. The microSD stays untouched as the boot fallback.

- [ ] **Step 5: Mark the spec implemented**

In the spec, replace the `**Status:** Designed.` line with:

```markdown
**Status:** Implemented 2026-08-22. Stage A and stage B complete: NFS mounts,
sensors, telegraf against the LAN InfluxDB, and homelab-scrapper from its own
flake with sops-provided credentials. Still open: `tailscale up` on pella, and
the EVO SSD migration.
```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-08-22-pella-phase2-services-design.md
git commit -m "docs(pella): mark phase 2 implemented"
```

---

## Still open after this plan

- `tailscale up` on pella — off-LAN access does not work until it is logged in
- `security.sudo.wheelNeedsPassword = false` on pella — deferred decision, not
  implemented by any task here
- Moving the root from the USB stick to the Samsung EVO SSD: re-`dd`, then grow
  by hand, because `sdImage.expandOnBoot` does not fire
- The AC88U cutover: reserve `.230` in its DHCP pool, place it centrally in the
  40x40 ft room with a wired run from the ONT corner
