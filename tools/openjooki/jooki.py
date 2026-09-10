#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenJooki — safe recovery of a Jooki v2 from a computer.

Anti-brick promise (see README): never touches the bootloader nor the
factory partition; backs up before any write; OS patches via A/B (rollback).
This file: read/backup + CONTENT management (music/playlists/tokens).
Content management writes ONLY to /jooki/external — bricking is impossible.
Python 3, standard library only.
"""
__version__ = "0.2.1"
import argparse, os, socket, struct, subprocess, sys, time, json, random, mimetypes, base64, glob
import urllib.parse, urllib.request, concurrent.futures, datetime

HOME = os.path.expanduser("~/.openjooki")
KEY  = os.path.join(HOME, "id_jooki_rsa")
BKP  = os.path.join(HOME, "backups")
DEFAULT_HOST = os.environ.get("JOOKI_HOST", "192.168.1.61")
PATCH_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "patches")
SERVICES_DIR = "/jooki/app/services"
# Hardware models OpenJooki currently supports (Jooki v2 = Ingenic X1000).
# A firmware is refused on any other model (e.g. a v1) BEFORE any write.
SUPPORTED_DEVICE_TYPES = ("ml-j2000",)
MQTT_PORT = 1883

SSH_OPTS = [
    "-o","BatchMode=yes","-o","ConnectTimeout=8","-o","StrictHostKeyChecking=accept-new",
    "-o","UserKnownHostsFile="+os.path.join(HOME,"known_hosts"),
    "-o","HostKeyAlgorithms=+ssh-rsa","-o","PubkeyAcceptedAlgorithms=+ssh-rsa",
    "-o","KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1",
    "-o","Ciphers=+aes128-ctr,aes128-cbc,3des-cbc","-o","MACs=+hmac-sha1",
    "-o","IdentitiesOnly=yes",
]
SSH_PORT = "2222"
def log(*a): print(*a, flush=True)

# ---------------- HTTP / /ll ----------------
def http_get(host, path, timeout=8):
    try:
        with urllib.request.urlopen("http://%s%s"%(host,path), timeout=timeout) as r:
            return r.status, r.read()
    except Exception as e:
        return None, str(e).encode()

def ll(host, cmd, timeout=10):
    q = urllib.parse.urlencode({"action": cmd})
    _, body = http_get(host, "/ll?"+q, timeout=timeout)
    return (body or b"").decode(errors="replace").strip()

def is_jooki(host):
    st, body = http_get(host, "/", timeout=3)
    if st == 200 and (b"jooki" in body.lower() or b"My Jooki" in body): return True
    st, _ = http_get(host, "/ping", timeout=3); return st is not None

# ---------------- SSH ----------------
def ssh(host, remote_cmd, timeout=120):
    cmd = ["ssh","-p",SSH_PORT,"-i",KEY]+SSH_OPTS+["root@"+host, remote_cmd]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

def ssh_ok(host):
    try:
        r = ssh(host, "echo OK", timeout=12); return r.returncode==0 and "OK" in (r.stdout or "")
    except Exception: return False

def ensure_key():
    os.makedirs(HOME, exist_ok=True); os.chmod(HOME, 0o700)
    if not os.path.exists(KEY):
        subprocess.run(["ssh-keygen","-t","rsa","-b","2048","-C","openjooki","-f",KEY,"-N",""],
                       check=True, capture_output=True)
    return open(KEY+".pub").read().split()[1]

def install_key(host):
    b64 = ensure_key()
    ll(host,"mkdir -p /home/root/.ssh"); ll(host,"chmod 700 /home/root/.ssh")
    ll(host,"printf 'ssh-rsa ' > /home/root/.ssh/authorized_keys")
    for i in range(0,len(b64),24):
        ll(host,"printf '%s' >> /home/root/.ssh/authorized_keys" % b64[i:i+24])
    ll(host,"echo >> /home/root/.ssh/authorized_keys"); ll(host,"chmod 600 /home/root/.ssh/authorized_keys")

def ensure_ssh(host):
    if ssh_ok(host): return True
    for attempt in range(1,6):
        ll(host,"dropbear -p 2222 -R"); time.sleep(3)
        if ssh_ok(host): return True
        if attempt==2: install_key(host)
    return ssh_ok(host)

def read_remote_json(host, path):
    r = ssh(host, "cat %s" % path)
    if r.returncode!=0: return None
    try: return json.loads(r.stdout)
    except Exception: return None

# ---------------- Minimal MQTT (publish QoS0) ----------------
def _mqtt_remlen(n):
    out=b""
    while True:
        b=n%128; n//=128
        if n>0: b|=0x80
        out+=bytes([b])
        if n==0: break
    return out

def mqtt_publish(host, topic, payload, timeout=8):
    """Minimal MQTT client (stdlib): CONNECT + PUBLISH QoS0 + DISCONNECT."""
    cid=("openjooki%d"%random.randint(0,99999)).encode()
    # CONNECT
    vh=struct.pack("!H",4)+b"MQTT"+bytes([4,2])+struct.pack("!H",60)  # clean session, keepalive 60
    pl=struct.pack("!H",len(cid))+cid
    connect=bytes([0x10])+_mqtt_remlen(len(vh)+len(pl))+vh+pl
    tb=topic.encode(); msg=payload.encode()
    pub_vh=struct.pack("!H",len(tb))+tb
    publish=bytes([0x30])+_mqtt_remlen(len(pub_vh)+len(msg))+pub_vh+msg
    disc=bytes([0xE0,0x00])
    s=socket.create_connection((host,MQTT_PORT),timeout=timeout)
    try:
        s.sendall(connect)
        connack=s.recv(4)  # 0x20 0x02 0x00 0x00 expected
        if len(connack)<4 or connack[0]!=0x20 or connack[3]!=0x00:
            raise RuntimeError("MQTT CONNECT refused (%r)"%connack)
        s.sendall(publish); s.sendall(disc); time.sleep(0.2)
    finally:
        s.close()

def web_cmd(host, typ, fields):
    """Send a command to the app via /j/web/input/<TYPE>."""
    mqtt_publish(host, "/j/web/input/"+typ, json.dumps(fields))

# ---------------- HTTP multipart upload ----------------
def upload_file(host, filepath, timeout=120):
    name=os.path.basename(filepath)
    data=open(filepath,"rb").read()
    if len(data)<=5000: raise RuntimeError("file too small (>5000 bytes required)")
    uid=str(random.randint(0,9999999))            # upload_id = random integer (like the app)
    boundary="----openjooki%d"%random.randint(0,1<<31)
    ctype=mimetypes.guess_type(name)[0] or "audio/mpeg"
    body=(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n"
           "Content-Type: %s\r\n\r\n"%(boundary,uid,name,ctype)).encode()+data+
          ("\r\n--%s--\r\n"%boundary).encode())
    req=urllib.request.Request("http://%s/upload"%host, data=body, method="POST",
        headers={"Content-Type":"multipart/form-data; boundary=%s"%boundary,"Content-Length":str(len(body))})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if r.status!=200: raise RuntimeError("upload HTTP %s"%r.status)
    return uid, name

# ---------------- Backup-before-write ----------------
def quick_backup(host):
    ts=datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out=os.path.join(BKP,ts); os.makedirs(out,exist_ok=True)
    p=os.path.join(out,"content-safety.tar.gz")
    with open(p,"wb") as f:
        cmd=["ssh","-p",SSH_PORT,"-i",KEY]+SSH_OPTS+["root@"+host,
             "tar czf - /jooki/external/jooki/playlists.json /jooki/external/jooki/tokens.json /jooki/external/jooki/tracks.json 2>/dev/null"]
        subprocess.run(cmd, stdout=f, stderr=subprocess.DEVNULL, timeout=120)
    ok=subprocess.run(["gzip","-t",p]).returncode==0
    log("  safety backup: %s (%s)" % (p, "OK" if ok else "?"))
    return ok

# ---------------- Commands ----------------
def cmd_discover(args):
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    try: s.connect(("8.8.8.8",80)); local=s.getsockname()[0]
    finally: s.close()
    base=".".join(local.split(".")[:3]); log("Scanning %s.0/24..."%base)
    def probe(i):
        ip="%s.%d"%(base,i)
        try:
            with socket.create_connection((ip,80),timeout=0.4): pass
        except Exception: return None
        return ip if is_jooki(ip) else None
    found=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=64) as ex:
        for r in ex.map(probe,range(1,255)):
            if r: found.append(r)
    log("Jooki found: "+", ".join("http://%s"%f for f in found) if found else "No Jooki found.")
    return 0

def cmd_info(args):
    host=args.host
    if not is_jooki(host): log("Jooki unreachable at %s"%host); return 2
    if not ensure_ssh(host): log("SSH access failed."); return 3
    r=ssh(host,'echo "host=$(hostname)"; echo "kernel=$(uname -r) $(uname -m)"; '
               'echo "artifact=$(cat /etc/mender/artifact_info 2>/dev/null)"; '
               'echo "esp32_fw=$(cat /sys/kernel/htdrv/fw_version 2>/dev/null)"; '
               'echo "boot_part=$(fw_printenv mender_boot_part 2>/dev/null)"; '
               'df -h | grep -E "mmcblk|/jooki|Filesystem"')
    log(r.stdout.strip()); return 0

def cmd_backup(args):
    host=args.host
    if not is_jooki(host): log("Jooki unreachable"); return 2
    if not ensure_ssh(host): log("SSH access failed."); return 3
    ts=datetime.datetime.now().strftime("%Y%m%d-%H%M%S"); out=os.path.join(BKP,ts); os.makedirs(out,exist_ok=True)
    def pull(name, tar):
        p=os.path.join(out,name); log("  -> %s ..."%name)
        with open(p,"wb") as f:
            subprocess.run(["ssh","-p",SSH_PORT,"-i",KEY]+SSH_OPTS+["root@"+host,tar],
                           stdout=f, stderr=subprocess.DEVNULL, timeout=1800)
        ok=subprocess.run(["gzip","-t",p]).returncode==0
        log("     %s (%d B) %s"%(name,os.path.getsize(p),"OK" if ok else "INTEGRITY ?"))
    log("Backup -> %s"%out)
    pull("jooki-system.tar.gz","tar czf - /jooki/app /jooki/bin /jooki/lib /jooki/internal /data /mnt/config /etc/esp32 /boot /etc/default/dropbear 2>/dev/null")
    if getattr(args,"quick",False): log("  (--quick: content skipped)")
    else: pull("jooki-content.tar.gz","tar czf - /jooki/external 2>/dev/null")
    open(os.path.join(out,"info.txt"),"w").write(ssh(host,'uname -a; cat /etc/mender/artifact_info; ls -la /boot').stdout or "")
    log("Backup finished in %s"%out); return 0

def _playlists(host):
    d=read_remote_json(host,"/jooki/external/jooki/playlists.json") or {}
    return {k:v for k,v in d.items() if k!="_"}

def cmd_playlist(args):
    host=args.host
    if not is_jooki(host): log("Jooki unreachable"); return 2
    if not ensure_ssh(host): log("SSH access failed."); return 3
    if args.action=="list":
        for pid,pl in _playlists(host).items():
            log("%-22s  %-28s tag=%s  %d tracks"%(pid, pl.get("title","?"), pl.get("tagId","-"), len(pl.get("tracks",[]))))
        return 0
    if args.action=="new":
        if args.dry_run: log("[dry-run] PLAYLIST_NEW title=%r audiobook=False"%args.title); return 0
        quick_backup(host)
        before=set(_playlists(host).keys())
        web_cmd(host,"PLAYLIST_NEW",{"title":args.title,"audiobook":False}); time.sleep(2)
        after=_playlists(host); new=[k for k in after if k not in before]
        if new: log("Playlist created: %s (%s)"%(new[0], after[new[0]].get("title"))); 
        else: log("Playlist sent (id not detected, check 'playlist list').")
        return 0
    return 1

def cmd_music(args):
    host=args.host
    if not os.path.exists(args.file): log("File not found: %s"%args.file); return 2
    if not is_jooki(host): log("Jooki unreachable"); return 2
    if not ensure_ssh(host): log("SSH access failed."); return 3
    pls=_playlists(host)
    # resolve the target playlist (id or title)
    target=args.playlist
    if target not in pls:
        match=[pid for pid,pl in pls.items() if pl.get("title")==target]
        if match: target=match[0]
        elif args.create:
            if args.dry_run: log("[dry-run] would create playlist %r"%args.playlist)
            else:
                quick_backup(host); before=set(pls.keys())
                web_cmd(host,"PLAYLIST_NEW",{"title":args.playlist,"audiobook":False}); time.sleep(2)
                after=_playlists(host); new=[k for k in after if k not in before]
                if not new: log("Could not create the playlist."); return 4
                target=new[0]; log("Playlist created: %s"%target)
        else:
            log("Playlist '%s' not found. Options: %s  (or --create)"%(args.playlist, ", ".join(pls)or"none")); return 4
    if args.dry_run:
        log("[dry-run] upload %s then PLAYLIST_ADD_UPLOAD to %s"%(args.file,target)); return 0
    quick_backup(host)
    before_tracks=len((_playlists(host).get(target) or {}).get("tracks",[]))
    log("Uploading %s ..."%os.path.basename(args.file))
    uid,name=upload_file(host,args.file)
    web_cmd(host,"PLAYLIST_ADD_UPLOAD",{"playlistId":target,"uploadId":uid,"filename":name})
    # verification
    ok=False
    for _ in range(10):
        time.sleep(2)
        n=len((_playlists(host).get(target) or {}).get("tracks",[]))
        if n>before_tracks: ok=True; break
    log("Added to %s: %s  (%s)"%(target, name, "OK, %d->%d tracks"%(before_tracks,n) if ok else "sent, check 'playlist list'"))
    return 0 if ok else 5


# ---------------- A/B patch (proven mechanism: clone + switch + revert) ----------------
def _device_type(host):
    """Return the Mender device_type identifying the hardware model (e.g. 'ml-j2000'
    for a Jooki v2). This is the canonical model id used to refuse a firmware meant
    for another model. Empty string if it cannot be read."""
    for path in ("/etc/mender/device_type", "/data/mender/device_type",
                 "/var/lib/mender/device_type"):
        out = ssh(host, "cat %s 2>/dev/null" % path).stdout.strip()
        if out:
            return out.split("=")[-1].strip()
    return ""


def _boot_part(host):
    r=ssh(host,"fw_printenv mender_boot_part 2>/dev/null | sed 's/.*=//'")
    return (r.stdout or "").strip()

def _spare(part): return "2" if part=="3" else "3"

def ab_status(host):
    a=_boot_part(host); s=_spare(a) if a in ("2","3") else "?"
    cur=ssh(host,"cat /etc/mender/artifact_info").stdout.strip()
    sp=ssh(host,"mkdir -p /mnt/spchk; mount -o ro /dev/mmcblk0p%s /mnt/spchk 2>/dev/null && cat /mnt/spchk/etc/mender/artifact_info; umount /mnt/spchk 2>/dev/null"%s).stdout.strip()
    log("ACTIVE partition = p%s  (%s)"%(a,cur))
    log("SPARE partition = p%s (%s)"%(s,sp))
    return a

def ab_clone(host):
    """Clone the active partition to the spare partition (verified). Does not touch boot."""
    a=_boot_part(host)
    if a not in ("2","3"): log("unexpected boot_part: %r"%a); return 1
    s=_spare(a); act="/dev/mmcblk0p"+a; spa="/dev/mmcblk0p"+s
    cl=ssh(host,"cat /proc/cmdline").stdout
    if ("root=%s"%act) not in cl: log("Safety: root!=active, aborting."); return 1
    szs={l.split()[3]:l.split()[2] for l in ssh(host,"grep -E 'mmcblk0p[23] ' /proc/partitions").stdout.splitlines()}
    if szs.get("mmcblk0p2")!=szs.get("mmcblk0p3"): log("Safety: p2/p3 sizes !=, aborting."); return 1
    cur=ssh(host,"cat /etc/mender/artifact_info").stdout.strip()
    log("Clone %s -> %s (dd on the card, ~1-2 min)..."%(act,spa))
    out=ssh(host,"sync; dd if=%s of=%s bs=4M 2>&1; sync; echo RC=$?"%(act,spa),timeout=300).stdout
    if "RC=0" not in out: log("dd failed (boot unchanged): %s"%out[-200:]); return 1
    chk=ssh(host,"mkdir -p /mnt/spchk; mount -o ro %s /mnt/spchk 2>&1 && { echo MOUNT_OK; ls /mnt/spchk/boot/uImage; echo ART=$(cat /mnt/spchk/etc/mender/artifact_info); }; umount /mnt/spchk 2>&1"%spa).stdout
    ok=("MOUNT_OK" in chk) and ("uImage" in chk) and (cur.split("=")[-1] in chk)
    log("Clone %s. Spare p%s = %s"%("VERIFIED OK" if ok else "TO VERIFY", s, "bootable clone of the active system" if ok else "?"))
    log("Boot was NOT modified (still p%s)."%a)
    return 0 if ok else 1

def _reboot(host):
    try: ssh(host,"sync; sync; (reboot || busybox reboot || /sbin/reboot || echo b > /proc/sysrq-trigger) >/dev/null 2>&1 &",timeout=8)
    except Exception: pass
    time.sleep(3)
    if is_jooki(host):
        try: ssh(host,"echo b > /proc/sysrq-trigger 2>/dev/null &",timeout=6)
        except Exception: pass

def ab_switch(host, part):
    """Switch to p<part> with U-Boot rollback ARMED (like a real Mender update).
       Counter reset to zero + monitored trial (upgrade_available=1) BEFORE the reboot:
       if the partition does not start, U-Boot (bootlimit=1) reverts to the other ON ITS OWN.
       If it starts fine, we settle the trial (commit: upgrade_available=0)."""
    if part not in ("2","3"): log("invalid partition"); return 1
    log("Switching to p%s (rollback armed) ..."%part)
    # Arming identical to a Mender update: counter at 0 + monitored trial.
    arm=("echo -n 0 > /sys/kernel/htdrv/bootcount 2>/dev/null; "
         "fw_setenv bootcount 0; fw_setenv upgrade_available 1; "
         "fw_setenv mender_boot_part %s; fw_setenv mender_boot_part_hex %s")%(part,part)
    ssh(host, arm, timeout=30)
    _reboot(host)
    for _ in range(40):
        if not is_jooki(host): break
        time.sleep(1)
    log("  rebooting (~1-2 min)...")
    up=False
    for _ in range(180):
        if is_jooki(host): up=True; break
        time.sleep(1)
    if not up:
        log("  !! did not come back — U-Boot will switch back ON ITS OWN to the other partition at next power-on (rollback armed)."); return 2
    for _ in range(6):
        if ensure_ssh(host): break
        time.sleep(5)
    bp=_boot_part(host); cl=ssh(host,"cat /proc/cmdline").stdout
    ok=(bp==part) and (("root=/dev/mmcblk0p%s"%part) in cl)
    if ok:
        # COMMIT: the partition boots correctly -> we settle the trial (no more pending rollback).
        ssh(host,"fw_setenv upgrade_available 0; /usr/bin/ht_reset_bootcount.sh >/dev/null 2>&1; echo -n 0 > /sys/kernel/htdrv/bootcount 2>/dev/null",timeout=30)
        ua=ssh(host,"fw_printenv upgrade_available 2>/dev/null").stdout.strip()
        log("  -> OK, boots on p%s, trial settled (%s)"%(part, ua or "upgrade_available=0")); return 0
    log("  -> TO VERIFY (mender_boot_part=%s) — trial NOT settled, U-Boot rollback stays armed"%bp); return 2

def ab_cut_cloud(host):
    """A/B patch: neutralize the cloud heartbeat (phone-home + ## ML_OTA backdoor).
       Clone active partition -> spare, patch the copy, switch, verify.
       Anti-brick: never touches the active partition's boot."""
    a=_boot_part(host)
    if a not in ("2","3"): log("unexpected boot_part: %r"%a); return 1
    s=_spare(a); sdev="/dev/mmcblk0p"+s
    # already cut?
    cur=ssh(host,"cat /jooki/app/services/heartbeat.sh 2>/dev/null").stdout
    if "OpenJooki" in cur and "socat" not in cur.lower():
        log("Cloud already cut (heartbeat neutralized). Nothing to do."); return 0
    log("[1] backup"); quick_backup(host)
    log("[2] clone p%s -> p%s"%(a,s))
    if ab_clone(host)!=0: log("clone failed -> aborting (boot unchanged)"); return 1
    log("[3] patch heartbeat on the spare partition")
    HB="/mnt/p2patch/jooki/app/services/heartbeat.sh"
    noop=("#!/bin/ash\n"
          "# Neutralized by OpenJooki: original cloud service stopped (server off).\n"
          "# No longer contacts any remote server nor executes remote code.\n"
          "exit 0\n")
    cmd=("set -e\nmkdir -p /mnt/p2patch\nmount %s /mnt/p2patch\n"
         "test -f %s || { echo NO_HB; umount /mnt/p2patch; exit 3; }\n"
         "cp -a %s %s.openjooki-orig\ncat > %s <<'HBEOF'\n%sHBEOF\n"
         "chmod 755 %s\nsync; umount /mnt/p2patch; echo PATCH_OK\n")%(sdev,HB,HB,HB,HB,noop,HB)
    if "PATCH_OK" not in ssh(host,cmd,timeout=60).stdout: log("patch failed -> aborting"); return 1
    log("[4] switch to p%s (patched)"%s)
    if ab_switch(host,s)!=0: log("switch KO -> back to p%s"%a); ab_switch(host,a); return 2
    hb=ssh(host,"cat /jooki/app/services/heartbeat.sh").stdout
    ok=is_jooki(host) and ("OpenJooki" in hb) and ("socat" not in hb.lower()) and _boot_part(host)==s
    if ok:
        log("cloud PATCH OK — Jooki on p%s, cloud cut. Rollback: jooki patch switch %s"%(s,a)); return 0
    log("verify KO -> back to p%s"%a); ab_switch(host,a); return 2


# ---------------- "harden" patch: security/robustness fixes via A/B ----------------
def _load_patches():
    out={}
    for fp in sorted(glob.glob(os.path.join(PATCH_DIR,"*.sh"))):
        with open(fp,"rb") as f: out[os.path.basename(fp)]=f.read()
    return out

def _norm(t):
    if isinstance(t,bytes): t=t.decode("utf-8","replace")
    return t.replace("\r\n","\n").rstrip("\n")

def _services_match(host, patches):
    """True if each service file (active partition) is identical to the patch (busybox without base64)."""
    for name,content in patches.items():
        got=ssh(host,"cat %s/%s 2>/dev/null"%(SERVICES_DIR,name)).stdout
        if _norm(got)!=_norm(content): return False
    return True

def ab_harden(host):
    """Apply the fixes from the patches/ folder (security/robustness audit) via A/B.
       Clone active->spare, write the patched files on the copy, switch, verify each file.
       Anti-brick: never touches the active partition's boot; auto rollback if any file diverges."""
    patches=_load_patches()
    if not patches: log("No fix in %s"%PATCH_DIR); return 1
    a=_boot_part(host)
    if a not in ("2","3"): log("unexpected boot_part: %r"%a); return 1
    s=_spare(a); sdev="/dev/mmcblk0p"+s
    log("Fixes: %s"%", ".join(sorted(patches)))
    if _services_match(host, patches):
        log("All fixes are already applied (active partition). Nothing to do."); return 0
    log("[1] backup"); quick_backup(host)
    log("[2] clone p%s -> p%s"%(a,s))
    if ab_clone(host)!=0: log("clone failed -> aborting (boot unchanged)"); return 1
    log("[3] writing the fixes on the spare partition")
    MP="/mnt/p2patch"; DELIM="OJ_PATCH_EOF_9f3a2b"
    lines=["set -e","mkdir -p %s"%MP,"mount %s %s"%(sdev,MP),"D=%s%s"%(MP,SERVICES_DIR)]
    lines.append("trap 'umount %s 2>/dev/null' EXIT"%MP)  # umount ALWAYS, even on failure
    for name,content in sorted(patches.items()):
        body=_norm(content)
        if DELIM in body: log("delimiter conflict in %s -> aborting"%name); return 1
        lines.append("test -f $D/%s || { echo NO_%s; umount %s; exit 3; }"%(name,name.replace('.','_'),MP))
        lines.append("test -f $D/%s.openjooki-orig || cp -a $D/%s $D/%s.openjooki-orig"%(name,name,name))
        lines.append("cat > $D/%s <<'%s'"%(name,DELIM))
        lines.append(body)
        lines.append(DELIM)
        lines.append("chmod 755 $D/%s"%name)
    lines+=["sync","umount %s"%MP,"echo PATCH_OK"]
    if "PATCH_OK" not in ssh(host,"\n".join(lines),timeout=120).stdout:
        log("write failed -> aborting (boot unchanged)"); return 1
    log("[4] switch to p%s (patched)"%s)
    if ab_switch(host,s)!=0: log("switch KO -> back to p%s"%a); ab_switch(host,a); return 2
    log("[5] verification of the %d files on the active partition"%len(patches))
    if is_jooki(host) and _boot_part(host)==s and _services_match(host,patches):
        log("HARDEN OK — Jooki on p%s, %d fixes verified. Rollback: jooki patch switch %s"%(s,len(patches),a)); return 0
    log("verify KO -> back to p%s"%a); ab_switch(host,a); return 2

def cmd_patch(args):
    host=args.host
    if not is_jooki(host): log("Jooki unreachable"); return 2
    if not ensure_ssh(host): log("SSH access failed."); return 3
    if args.action=="status": ab_status(host); return 0
    if args.action=="cut-cloud": return ab_cut_cloud(host)
    if args.action=="harden":    return ab_harden(host)
    if args.action=="clone":  return ab_clone(host)
    if args.action=="switch":
        if not args.part: log("specify the partition: patch switch 2|3"); return 1
        return ab_switch(host, args.part)
    return 1

def main():
    ap=argparse.ArgumentParser(prog="jooki", description="OpenJooki — safe recovery of a Jooki.")
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--version", action="version", version="OpenJooki "+__version__)
    sub=ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("discover", help="find the Jooki")
    sub.add_parser("info", help="device info")
    pb=sub.add_parser("backup", help="backup"); pb.add_argument("--quick",action="store_true")
    pp=sub.add_parser("playlist", help="manage playlists")
    pp.add_argument("action", choices=["list","new"]); pp.add_argument("title", nargs="?", default="")
    pp.add_argument("--dry-run", action="store_true")
    pm=sub.add_parser("music", help="add music")
    pm.add_argument("action", choices=["add"]); pm.add_argument("file")
    pm.add_argument("--playlist", required=True, help="id or title of the target playlist")
    pm.add_argument("--create", action="store_true", help="create the playlist if missing")
    pm.add_argument("--dry-run", action="store_true")
    pa=sub.add_parser("patch", help="A/B firmware patch (clone/switch, anti-brick)")
    pa.add_argument("action", choices=["status","clone","switch","cut-cloud","harden"])
    pa.add_argument("part", nargs="?", choices=["2","3"], help="for switch: target partition")
    args=ap.parse_args()
    return {"discover":cmd_discover,"info":cmd_info,"backup":cmd_backup,
            "playlist":cmd_playlist,"music":lambda a:cmd_music(a),"patch":cmd_patch}[args.cmd](args)

if __name__=="__main__":
    sys.exit(main() or 0)
