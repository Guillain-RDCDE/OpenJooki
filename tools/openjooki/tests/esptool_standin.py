#!/usr/bin/env python3
# Stand-in for esptool.py on the Jooki's own python3 (device_esp32_trial.sh): takes the exact arguments of flash.sh,
# writes each file at its offset into /flash.bin (the chip's 16 MiB flash) and logs the call.
import sys
args = sys.argv[1:]
log = open("/esptool.log", "a"); log.write(" ".join(args) + "\n"); log.close()
port = args[args.index("-p") + 1]; open(port, "rb").close()      # the serial line must exist
i = args.index("write_flash") + 1
flags = {}
while args[i].startswith("--"):
    flags[args[i]] = args[i + 1]; i += 2
assert flags == {"--flash_mode": "dio", "--flash_size": "detect", "--flash_freq": "80m"}, flags
pairs = args[i:]
assert len(pairs) % 2 == 0 and pairs
with open("/flash.bin", "r+b") as f:
    for off, name in zip(pairs[::2], pairs[1::2]):
        data = open(name, "rb").read()
        f.seek(int(off, 0)); f.write(data)
        print("Wrote %d bytes at %s" % (len(data), off))
print("Hash of data verified.")
