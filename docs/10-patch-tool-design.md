# OpenJooki Tool — tool design (computer side)

Goal: a **simple, auditable tool that cannot brick** a Jooki, to share on GitHub.
It runs on a computer (Mac/Linux/Windows) and talks to the Jooki over the local
network. It replaces the dead app AND lets you patch the firmware **by relying on
the original anti-brick mechanism (Mender A/B)**.

## Safety promise (what we put front and center in the README)
1. **Backup first, always.** No write without a verified backup beforehand.
2. **We never write to the running system** for an OS patch: we write to the
   **inactive** partition (A/B).
3. **We NEVER touch** the bootloader (U-Boot/SPL) or the factory partition (p1).
   These are the only real brick vectors — the tool doesn't offer them.
4. **Automatic rollback**: an OS patch boots once; if it doesn't "commit,"
   U-Boot reverts on its own to the old system (native Mender mechanism).
5. **Reversible**: the factory partition (p1) and the old A/B partition stay
   intact as safety nets.
6. **Readable code** (a Python stdlib CLI, not an opaque binary). Everything is
   visible.

## Ground-truth recap (extracted from the device)
- SD card partitions: p1 factory · **p2 rootfs A** · **p3 rootfs B** · p4 swap ·
  p5 /data · p6 /mnt/config · p7 /jooki/external (content).
- Boot: U-Boot loads `/boot/uImage` from the active partition (p2 **or** p3),
  `bootargs ... root=<A/B> rootfstype=ext4 rw`. RAM = **32 MB** (stay light).
- Rollback: `mender_altbootcmd` / `upgrade_available` / `mender_try_to_recover`.
- `mender` is present on the device; rootfs mounted `rw`.
- Access: root SSH via **RSA** key + dropbear port 2222 (cf. docs/06).

## 3-level patch model (from safest to most advanced)
### Level 0 — Content (impossible to brick)
Music, playlists, tokens: only writes into `/jooki/external`. Zero risk.
### Level 1 — OS patch via "clone to the spare partition" (anti-brick)
1. Full backup (data + both rootfs partitions).
2. `dd` the **active** partition to the **inactive** one (identical clone).
3. Mount the inactive one, apply the patch (e.g. disable the cloud heartbeat,
   add our service) — **never** on the running system.
4. Flip U-Boot to boot the inactive one **once** (`upgrade_available=1`).
5. Reboot. If OK → `mender -commit` (makes it permanent). Otherwise → auto
   rollback.
   → The original system stays intact no matter what.
### Level 2 — ESP32 firmware (separate, opt-in)
Reflash `jooki_v2.bin` via `flash.sh`/esptool. The ESP32 has its own factory
partition + OTA (`ota_data_initial.bin`) as a net. Offered separately, with a
warning.

## What the tool does NOT do (by design)
- Write the bootloader / SPL / factory partition.
- Modify the running system for an OS patch.
- Flash anything without a verified backup.

## Planned commands (CLI)
    jooki discover                 # find the Jooki on the network
    jooki info                     # device info (versions, battery, availability)
    jooki backup [--full]          # data (+ disk image with --full)
    jooki music add <folder>       # add MP3s (level 0)
    jooki playlist ...             # create/edit playlists, associate tokens
    jooki enable-ssh               # root access (RSA key, dropbear 2222)
    jooki patch <patch-file>       # level 1 OS patch (A/B clone + rollback)
    jooki commit / rollback        # confirm or cancel an OS patch
    jooki esp32-flash <fw>         # level 2 (opt-in, warning)
Every writing command: automatic backup + confirmation + --dry-run.

## Tech stack (to inspire trust)
- **Python 3, standard library only** (subprocess to `ssh`/`scp`/`curl`). No
  opaque dependency. A clear repo, a README explaining the anti-brick promise,
  an open license.

## ✅ VALIDATED ON THE REAL JOOKI (09/2026)
- **Rollback**: the bootcount is managed by the **ESP32**
  (`/sys/kernel/htdrv/bootcount`, reset to 0 at boot by
  `/usr/bin/ht_reset_bootcount.sh`) — a **hardware watchdog**. `bootlimit=1` +
  `mender_altbootcmd` + `mender` 2.6.1 (`mender commit`). Rootfs mounted **`sync`**
  (consistent writes → safe clone).
- **Clone** (`patch clone`): `dd` p_active → p_spare **on the card**, with
  guardrails (root==active, sizes p2==p3, never p1/p5/p6/p7). Verified: the spare
  partition mounts, contains `/boot/uImage` and the active system's artifact.
  **Proven, without touching the boot.**
- **Switch** (`patch switch`): tested **p3→p2→p3** under real conditions. The
  device rebooted, booted from the spare partition (the clone), came back online,
  then went back to p3. **A/B switch proven and reversible.**
- **Rollback ARMED (v0.1.2)**: before each switch, the tool arms the U-Boot
  rollback like a real Mender update — `htdrv/bootcount`=0 (+ env),
  `upgrade_available=1` (monitored trial). If the partition doesn't boot → U-Boot
  `bootlimit=1` + `mender_altbootcmd` **switches back on its own** at power-up. If
  it boots → **commit** (`upgrade_available=0` + `ht_reset_bootcount.sh`).
  **Verified 100%**: armed cycle p3→p2→p3, `upgrade_available` 0→(1 armed)→0
  cleared at each step, device intact.
- **Safety**: both partitions remain valid systems; the worst case leaves the
  device on a working system. The factory partition (p1) and the bootloader are
  never touched.

## What remains (honesty)
- **Automatic rollback** is now **armed by the tool** at every switch (v0.1.2):
  for OS patches (scripts, services) the net is complete and verified. The only
  unproven case remains **destructive** (deliberately breaking a partition to
  film U-Boot switching back): needlessly risky on the sole device. A
  **USB-serial** console is still advised **only** before patches that touch
  **the kernel/init/bootloader** (out of current scope).
- **First real safe patch** (doesn't touch the boot) = **cut the cloud
  heartbeat**: done by mounting the spare partition, neutralizing `heartbeat.sh`,
  then `patch switch`. Net: the reverse `patch switch` is proven.
