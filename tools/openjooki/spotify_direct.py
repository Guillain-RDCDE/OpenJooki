"""spotify_ctrl, patched to start a playlist at a track and time.

Spotify starts a saved preset at the top of its playlist, whatever track it names, so a
Spotify character set to resume could not continue where it stopped. Inside spotify_ctrl, the
Spotify library has an entry (0x418a98) that takes a context URI and playback options: track
index and time. The patch rewrites only the MQTT play_preset handler (0x405bd8, 164 bytes):
an 84-byte payload starting with "s" goes to that entry, any other payload to SpPlayPreset as
before. The payload is the context URI null-padded to 64 bytes, then five little-endian 32-bit
words: track index, 0, time in ms, 0, 0 (services.streaming builds it).

The patch is built from the Jooki's own copy, and only for the one build it was made for
(the 2022 firmware's): no Spotify code is shipped, and any other build is left alone.
"""
import hashlib, struct

ORIGINAL_SHA256 = "a043029f5fde6c987cf21c6d1aedaf1db11525196bc3962955cd5831b9a15ab8"
PATCHED_SHA256 = "0a16443bb6c95ad1f5d6dd9d53c6c0e9defa4dda436bc9ad2efb48cbf45a432c"
START, END = 0x405bd8, 0x405c7c   # the play_preset handler
LOAD = 0x400000                   # virtual address of file offset 0
FIRST_WORD = bytes.fromhex("4b00023c")   # lui v0, 0x4b: the original handler's first instruction

REGS = {"zero": 0, "v0": 2, "a0": 4, "a1": 5, "a2": 6, "a3": 7, "t0": 8, "t1": 9, "t2": 10,
        "t9": 25, "gp": 28, "sp": 29, "ra": 31}


def _handler():
    """The new play_preset handler, MIPS32 little-endian."""
    words, labels, branches = [], {}, []

    def imm(op, rt, rs, n): words.append((op << 26) | (REGS[rs] << 21) | (REGS[rt] << 16) | (n & 0xFFFF))
    def move(rd, rs): words.append((REGS[rs] << 21) | (REGS[rd] << 11) | 0x21)
    def nop(): words.append(0)
    def branch(op, rs, rt, label): branches.append((len(words), label)); imm(op, rt, rs, 0)
    def label(name): labels[name] = len(words)
    def call(): words.append((REGS["t9"] << 21) | (REGS["ra"] << 11) | 9); nop()   # jalr t9

    # the same prologue as the original: gp, a frame keeping ra and gp, the fifth argument
    # (the device alias) on the stack, a2/a3 = the payload and its length
    imm(15, "gp", "zero", 0x4a); imm(9, "gp", "gp", 0x1d0)
    imm(9, "sp", "sp", -0x30); imm(43, "ra", "sp", 0x2c); imm(43, "gp", "sp", 0x20)
    imm(15, "v0", "zero", 0x4b); imm(35, "t0", "v0", -0x553c); imm(43, "t0", "sp", 0x10)
    imm(9, "a2", "v0", -0x4c34); imm(35, "a3", "v0", -0x4c38)
    # clear the pending-play flag, as the original does; then 84 bytes starting with "s" or not
    imm(15, "t1", "zero", 0x4a); imm(43, "zero", "t1", -0x7208)
    imm(36, "t1", "a2", 0); imm(9, "t2", "zero", ord("s")); branch(5, "t1", "t2", "preset"); nop()
    imm(9, "t2", "zero", 84); branch(5, "a3", "t2", "preset"); nop()
    # entry(URI, options at byte 64, alias)
    move("a0", "a2"); imm(9, "a1", "a2", 64); move("a2", "t0")
    imm(15, "t9", "zero", 0x41); imm(13, "t9", "t9", 0x8a98); call()
    branch(4, "zero", "zero", "done"); nop()
    # SpPlayPreset(-1, 0, payload, length, alias), as the original
    label("preset"); imm(35, "t9", "gp", -0x7e3c); move("a1", "zero"); imm(9, "a0", "zero", -1); call()
    label("done"); imm(35, "gp", "sp", 0x20); imm(35, "ra", "sp", 0x2c)
    words.append((REGS["ra"] << 21) | 8); imm(9, "sp", "sp", 0x30)   # jr ra, frame popped in the delay slot
    for i, target in branches: words[i] |= (labels[target] - i - 1) & 0xFFFF
    code = b"".join(struct.pack("<I", w) for w in words)
    assert len(code) <= END - START
    return code.ljust(END - START, b"\0")


def patch(original):
    """The patched executable for the known original, or None for any other build."""
    if hashlib.sha256(original).hexdigest() != ORIGINAL_SHA256: return None
    off = START - LOAD
    if original[off:off + 4] != FIRST_WORD: return None
    patched = original[:off] + _handler() + original[END - LOAD:]
    if hashlib.sha256(patched).hexdigest() != PATCHED_SHA256: return None
    return patched


def is_patched(data): return hashlib.sha256(data).hexdigest() == PATCHED_SHA256
