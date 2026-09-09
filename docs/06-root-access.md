# Root access to the Jooki — the method that works (09/2026)

## Summary
SSH root access obtained. Two firmware pitfalls, both worked around:
1. The SSH server (**dropbear**, BusyBox 1.31.1) runs on port 22 with the
   `-w` option = **root login disabled**. → we start a 2nd instance on **2222**.
2. This dropbear **does NOT accept ed25519 keys** (minimal build). → you need an
   **RSA** key.

## Actual hardware (corrects the earlier docs)
- SoC: **Ingenic X1000** (XBurst V4.15, **MIPS**), not a Raspberry Pi.
- Machine: "Muuselabs Jooki J2000" (JOOKI_MACHINE=ml-j2000).
- Kernel 5.7.0, BusyBox 1.31.1 userspace. ESP32 co-processor for NFC/LED.
- SD card /dev/mmcblk0 (7.7 GB): p1 factory, p2/p3 rootfs A/B, p4 swap,
  p5 /data, p6 /mnt/config (vfat), p7 /jooki/external (5.2 GB, content).

## Where the data lives
- `/jooki/external/jooki/`: **the real data** (playlists, tokens, MP3s,
  cover art) — this is what changes.
- `/jooki/internal/`: factory test MP3s.
- `/data/`: `spotify/credentials.bin`, `mender/*` (OTA), `mode/*` (flags).
- `/mnt/config/jooki.conf`: editable config (/config endpoint).

## The access procedure (automated in run/)
1. Dedicated RSA key: `~/.ssh/id_jooki_rsa`.
2. Install the key via the Jooki's `/ll` endpoint — WARNING: `/ll` has a
   **length limit (~100 chars)** and breaks on pipes `|`. So we write
   `authorized_keys` **in 24-char chunks** with `printf ... >>`.
3. Start a root dropbear on 2222: `/ll?action=dropbear -p 2222 -R`.
4. Connect: `ssh jooki` (alias configured in ~/.ssh/config).

## SSH alias (~/.ssh/config)
    Host jooki
      HostName 192.168.1.61
      Port 2222
      User root
      IdentityFile ~/.ssh/id_jooki_rsa
      IdentitiesOnly yes
      HostKeyAlgorithms +ssh-rsa
      PubkeyAcceptedAlgorithms +ssh-rsa
      KexAlgorithms +diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
      Ciphers +aes128-ctr,aes128-cbc,3des-cbc
      MACs +hmac-sha1

## IMPORTANT — persistence
The dropbear on 2222 is started by hand: it **does not survive a reboot**.
After a restart, re-run step 3 (a single /ll request). In Phase 1 we'll make
root access persistent cleanly (removing `-w` / a boot-time service).

## /ll endpoint — syntax memo (home-grown parser)
- OK: `cmd arg`, `;`, `>`, `>>`, spaces, `/`, `+`, `printf`, redirections.
- NOT OK: commands > ~100 characters, pipes `|`, `for/do/done` loops.
- Reading back output: write to `/mnt/config/jooki.conf`, then read it
  via `GET /config` (the content shows up in a <textarea>).
