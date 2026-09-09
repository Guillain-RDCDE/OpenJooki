# Runbook — Phase 0: root access + full backup

Goal: obtain stable root access and a COMPLETE IMAGE of the SD card, plus an
archive of the data. After that, nothing is irreversible.

## Prerequisites
- Jooki powered on, on Wi-Fi, reachable: http://192.168.1.61
- An SSH key on the Mac. Check for one / create one:
  ```sh
  ls ~/.ssh/id_ed25519.pub 2>/dev/null || ssh-keygen -t ed25519 -C "jooki" -f ~/.ssh/id_ed25519 -N ""
  cat ~/.ssh/id_ed25519.pub
  ```

## Step 1 — Install the SSH key on the Jooki (via the interface)
1. Open http://192.168.1.61/config
2. The contents of `jooki.conf` appear in a text area. Add (or complete) a line
   that exports your public key into authorized_keys at boot, OR use the /ll
   endpoint to write it directly:
   ```
   http://192.168.1.61/ll?action=mkdir%20-p%20/home/root/.ssh
   http://192.168.1.61/ll?action=echo%20'<PUBLIC_KEY>'%20>>%20/home/root/.ssh/authorized_keys
   ```
   (⚠ URL-encode it; we'll do this cleanly together from Chrome.)
3. Test: `ssh root@192.168.1.61` → you should get in without a password.

## Step 2 — Recon (confirm the hardware)
```sh
ssh root@192.168.1.61 'uname -a; cat /proc/cpuinfo | tail; lsblk; df -h; cat /etc/mender/mender.conf'
```

## Step 3 — QUICK data backup (small, do it often)
From the Mac, in the project folder:
```sh
./scripts/jooki-backup.sh data
```
→ pulls playlists.json, tokens.json, audiocfg, uploads/, artwork/, config,
   ESP32 firmware, web UI bundle → backups/data-YYYYMMDD/

## Step 4 — COMPLETE SD card IMAGE (the "gold" backup)
The Jooki must be quiet (nothing playing). From the Mac:
```sh
./scripts/jooki-backup.sh image
```
→ compressed image of /dev/mmcblk0 in backups/ (~2-3 GB compressed).
It is THIS image that lets you restore everything or clone onto a fresh SD.

## Step 5 — Verify the backup
```sh
./scripts/jooki-backup.sh verify
```
Only move on to Phase 1 (cut the cloud) after a verified image.
