#!/usr/bin/env python3
"""jooki.py's A/B switch (patch switch, patch webui, the installer) against a scripted Jooki and clock.

A Jooki whose Wi-Fi starts slowly is back on the network minutes after a restart. The switch waits
for it as long as the Wi-Fi watchdog does, says it is still waiting, and when the Jooki stays out of
reach it leaves the armed trial alone: a switch back would go over a connection it no longer has.

  - back after 350 s: the trial on the new partition is committed;
  - never back: AB_LOST after BOOT_WAIT_S, a message that the trial is still armed, no switch back;
  - back on the wrong partition: the switch back to the old one still happens.

  python3 test_ab_switch.py        (no core, no root)
"""
import os, sys, types
import bench as B
sys.path.insert(0, os.path.join(B.REPO, "tools", "openjooki"))
import jooki

R = B.Results(lead=""); check = R.check

class Jooki:
    """Reachable until it restarts, then out of reach for back_after s (None: never back).
       A look while it is away fails at once, as it does on the LAN (the old count of 180 looks
       gave up after three minutes), or takes look_s, up to is_jooki's HTTP timeouts."""
    def __init__(s, back_after, boots_on=None, look_s=0):
        s.t, s.down, s.back_after, s.boots_on, s.look_s = 0.0, None, back_after, boots_on, look_s
        s.cmds, s.out = [], []
    def up(s):
        if s.down is None: return True
        ok = s.back_after is not None and s.t - s.down >= s.back_after
        if not ok: s.t += s.look_s
        return ok
    def sleep(s, d): s.t += d
    def reboot(s, host): s.down = s.t
    def ssh(s, host, cmd, timeout=120):
        s.cmds.append(cmd)
        part = s.boots_on or s.arms()[-1]
        out = part if "mender_boot_part" in cmd and "fw_printenv" in cmd else \
              "root=/dev/mmcblk0p%s" % part if "cmdline" in cmd else ""
        return types.SimpleNamespace(stdout=out, returncode=0)
    def arms(s):
        """The partitions the tool armed, in order."""
        return [c.split("fw_setenv mender_boot_part ")[1].split(";")[0] for c in s.cmds if "fw_setenv mender_boot_part " in c]

def run(j, fn, *a):
    jooki.is_jooki = lambda host: j.up()
    jooki.ensure_ssh = lambda host: True
    jooki.ssh = j.ssh
    jooki._reboot = j.reboot
    jooki.log = lambda *x: j.out.append(" ".join(str(y) for y in x))
    jooki.time = types.SimpleNamespace(sleep=j.sleep, monotonic=lambda: j.t, time=lambda: j.t)
    return fn("jooki", *a)

# AB1 a Jooki back 350 s after the restart (the slow Wi-Fi start seen on the user's Jooki)
j = Jooki(back_after=350)
rc = run(j, jooki.ab_switch, "3")
check("AB1 back after 350 s: the switch succeeds", rc == 0, (rc, j.out))
check("AB1 ... and commits the trial", any("upgrade_available 0" in c for c in j.cmds), j.cmds)
check("AB1 ... saying it is still waiting while it waits", any("still waiting (300 s)" in x for x in j.out), j.out)

# AB2 a Jooki that does not come back: the trial stays armed, nothing more is sent
j = Jooki(back_after=None)
rc = run(j, jooki.switch_or_back, "3", "2")
check("AB2 never back: the switch says so (AB_LOST)", rc == jooki.AB_LOST, (rc, j.out))
check("AB2 ... after the watchdog's 10 min, not before", jooki.BOOT_WAIT_S <= j.t - j.down < jooki.BOOT_WAIT_S + 10, j.t - j.down)
check("AB2 ... with no switch back to p2", j.arms() == ["3"], j.arms())
said = " ".join(j.out)
check("AB2 ... and says the trial is still armed and what a restart does", "still armed" in said and "back on p2" in said, j.out)

j = Jooki(back_after=None, look_s=6)
rc = run(j, jooki.ab_switch, "3")
check("AB2 ... the same 10 min when each look takes is_jooki's full 6 s", rc == jooki.AB_LOST and jooki.BOOT_WAIT_S <= j.t - j.down < jooki.BOOT_WAIT_S + 10, (rc, j.t - j.down))

# AB3 a Jooki back on the wrong partition: back to the old one, as before
j = Jooki(back_after=60, boots_on="2")
rc = run(j, jooki.switch_or_back, "3", "2")
check("AB3 back on the wrong partition: the switch fails", rc == 2, (rc, j.out))
check("AB3 ... and the tool switches back to p2", j.arms() == ["3", "2"], j.arms())

R.finish()
