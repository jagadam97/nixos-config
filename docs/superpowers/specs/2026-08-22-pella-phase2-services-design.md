# pella — Phase 2: NixOS services host

**Date:** 2026-08-22
**Status:** Implemented 2026-08-22. Stage A and stage B complete: NFS automounts,
sensors, telegraf writing to the LAN InfluxDB, and homelab-scrapper built from
its own flake with sops-provided credentials. Verified after a reboot - bucket
`pi` holds points tagged `host=pella` and the scraper reports 205 torrents every
10s.

Two findings worth carrying forward. telegraf and the scraper use *different*
InfluxDB tokens with different bucket scopes, so reusing one for the other gives
a 403 `insufficient permissions for write` that reads like a config bug. And a
sops secret must declare `restartUnits`, or a rotated value lands on disk while
the running service keeps the old one - the same 403, with nothing in the config
to explain it. Both secrets now declare it, which also means the pending token
rotation will apply on its own.

Still open: the InfluxDB tokens are the ones Debian used and are due for
rotation, and the root still lives on the USB stick rather than the EVO SSD.

Original status line follows.

**Status:** Designed. Phase 1 implemented — see
`docs/superpowers/specs/2026-08-22-pella-nixos-phase1-design.md`
**Host:** `pella`, Raspberry Pi 4B Rev 1.5, 4GB, `aarch64-linux`, 192.168.4.230

## Context

Phase 1 delivered a NixOS box that boots and stays reachable. Phase 2 was
supposed to make that box the household router. It no longer is.

An ASUS RT-AC88U (bought with an RT-AC68U) will own the network edge instead.
It does roughly 940 Mbps of NAT with Broadcom CTF against a ~450 Mbps line, so
throughput was never the deciding factor — keeping the household internet out
of this repo's critical path is. A router that any family member can power-cycle
back to working, configured in a web UI, is the right tool for that job. What is
lost is declarative router config; what is gained is that a bad `nixos-rebuild`
can no longer take the internet down.

So pella becomes the always-on services host and takes over what Debian ran.
Debian's services stopped when pella replaced it at 15:22 IST on 2026-08-22. The
card is intact and was mounted read-only to produce the inventory below.

## Goal

Everything Debian ran that is still wanted, running declaratively on pella, with
credentials in sops. Split into two stages so that nothing needing a secret
blocks the parts that do not.

## Non-goals

- Routing, PPPoE, nftables NAT, a DHCP server, SQM — the AC88U owns the edge
- `wol-server` — dropped. It was a Tailscale-bound WoL UI for waking razorback
- The `/mnt/hdd` NFS export — no disk is attached and storage lives on
  192.168.4.240. It also exported with `no_root_squash`, which will not be
  recreated
- The Loki output Debian's telegraf carried — it pointed at an unedited
  `logs-prod-014.grafana.net` placeholder
- Moving the root to the Samsung EVO SSD — a separate re-`dd` plus a manual grow
- home-manager on this host
- `nixos-autoupdate` — revisit once the box has been boring for a few weeks

## Inventory, from the Debian card

| Service | What it was | Disposition |
| --- | --- | --- |
| `homelab-scrapper` | qBittorrent metrics scraper, Go, `EnvironmentFile=/etc/homelab-scrapper.env` | Migrate. Private repo, no flake yet |
| `telegraf` | Metrics to InfluxDB v2 + a dead Loki endpoint | Migrate, InfluxDB only |
| NFS client | `/mnt/pve/{hd4000,bx500,bx1000}` from 192.168.4.240 | Migrate, module already exists |
| `smartd`, `lm-sensors` | Disk health and temperatures | Wire, leave off until the SSD |
| `wol-server` | Rust/axum WoL UI on `100.86.111.21:3000` | Drop |
| NFS export | `/mnt/hdd` to `192.168.4.0/24` | Drop |
| `tailscaled` | Remote access | Already running on pella |

## Network position

pella keeps `192.168.4.230/24` static on eth0 (`bcmgenet`, MAC-pinned to
`d8:3a:dd:24:76:1e`). The gateway stays `192.168.4.1` — the ONT today, the
AC88U after cutover — so the router swap changes nothing in pella's config. The
AC88U must reserve or exclude `.230` in its DHCP pool.

eth1 (the UE300, `r8152`) has no purpose now that the WAN is not pella's job. It
stays down and unconfigured; the phase 1 comment reserving it for PPPoE should
be corrected rather than left misleading.

Tailscale is enabled and running but still logged out — it needs `tailscale up`
completed before off-LAN access works.

## Stage A — no secrets

1. Import `modules/services/nfs-mounts.nix`. It already uses
   `x-systemd.automount` with `x-systemd.mount-timeout=10`, so an unreachable
   192.168.4.240 cannot hang boot. On a box with no console that property is the
   whole point, so it gets verified rather than assumed.
2. Add `lm_sensors`. Wire `services.smartd` but leave it disabled — SMART
   passthrough over a USB bridge is unreliable, and a unit that always fails
   teaches you to ignore alerts. It gets enabled when the EVO SSD arrives.
3. Package `homelab-scrapper` without running it: add `flake.nix` with
   `buildGoModule` to `jagadam97/homelab-scrapper`, add the flake input here,
   and write `modules/services/homelab-scrapper.nix` with `enable = false`.
   This proves the aarch64 Go build before secrets are in play.
4. Reboot with the boot guard armed, then confirm.

## Stage B — secrets

1. Derive pella's age key with `ssh-to-age` from its SSH host key. Add a
   `&pella` anchor and a `hosts/pella/secrets.yaml` creation rule (pella +
   admin) to `.sops.yaml`.
2. Populate `hosts/pella/secrets.yaml`. The values live in
   `/etc/homelab-scrapper.env` on the Debian card: `QBIT_URL`, `QBIT_API_KEY`,
   `INFLUX_URL`, `INFLUX_TOKEN`, `INFLUX_ORG`, `INFLUX_BUCKET`,
   `SCRAPE_INTERVAL`. Move the file into `sops -e` and shred the plaintext; do
   not print it. **Rotate the InfluxDB token first** — the old value was echoed
   into a session transcript on 2026-08-22.
3. Drop `sops.age.keyFile = "/var/lib/sops-nix/keys.txt"` from
   `hosts/pella/default.nix`. The default `sshKeyPaths` uses the host key the
   age key was derived from, so there is no key file to provision or lose.
4. Enable telegraf. The existing module hardcodes one endpoint, so it gains
   options for URL, organisation and bucket, defaulting to today's values so
   razorback and nauvoo are unaffected. pella sets
   `http://192.168.4.248:8086`, org `oracle`, bucket `pi`. Inputs as Debian had
   them, plus Pi thermals, minus `wireless` (wlan0 is unused).
5. Enable `homelab-scrapper`: `sops.secrets."homelab-scrapper.env"` owned by the
   service user, wired as `EnvironmentFile`, `enable = true`.

## Module design — homelab-scrapper

A static system user, not `DynamicUser`, so the sops secret can be owned by a
known uid. `Type=simple`, `Restart=on-failure`, `RestartSec=5s`. Hardening
mirrors the old wol-server unit, which was already strict: `NoNewPrivileges`,
`ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `PrivateDevices`,
`ProtectKernelTunables`, `ProtectKernelModules`, `ProtectControlGroups`,
`RestrictNamespaces`, `RestrictRealtime`, `RestrictSUIDSGID`, `LockPersonality`,
`MemoryDenyWriteExecute`, `SystemCallArchitectures=native`.

The service only makes outbound connections, to qBittorrent and InfluxDB, so it
needs no firewall change.

## Deployment

Deploys run from razorback, which is on the LAN with 16 cores and aarch64
binfmt:

```bash
nixos-rebuild switch --flake .#pella \
  --target-host jagadam97@192.168.4.230 --use-remote-sudo
```

Rebuilding on pella itself is the proven fallback — phase 1 verified it works.
Rollback is `nixos-rebuild --rollback`. Before any change that could affect
networking, re-arm the boot guard with `rm /var/lib/pella-boot-confirmed` so a
mistake returns the Pi to Debian without hands.

**Open decision:** `security.sudo.wheelNeedsPassword = false` on pella.
`--use-remote-sudo` prompts on every deploy otherwise. SSH there is key-only
with password authentication forced off, there is no console, and the phase 1
reboot loop lasted five hours only because a single root-owned file could not be
written remotely.

## Verification

- Each unit active, and still active after a reboot
- The sops secret exists with the right owner, and survives a reboot
- Fresh points in InfluxDB for both telegraf and the scrapper, not just a
  running process
- All three NFS automounts resolve on access
- A reboot with the guard armed, then confirmed

## Risks

- **Private repo fetch.** The flake input needs GitHub access wherever
  evaluation happens. The macbook and razorback are authenticated; pella is not
  necessarily, so evaluate and deploy from razorback or the macbook.
- **aarch64 Go build.** `buildGoModule` needs a pinned `vendorHash`, and the
  build runs under binfmt on razorback.
- **Token rotation blast radius.** razorback and nauvoo hold their own
  `INFLUX_TOKEN` for `influx.jagadam97.uk`. The leaked token was the Pi's, for
  the LAN InfluxDB at 192.168.4.248 — confirm they are genuinely separate before
  rotating.

## Open items

- Complete `tailscale up` on pella
- Rotate the leaked InfluxDB token
- Buy the AC88U and place it centrally in the 40x40 ft room, with a wired run
  from the ONT corner rather than a corner mount
- Migrate the root from the USB stick to the Samsung EVO SSD
